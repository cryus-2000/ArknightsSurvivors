## 编队干员的基类（docs/23）：干员跟随博士、自动输出、没有生命值；定义 game.gd / squad.gd 调用的接口，默认实现为空。
## 每个干员 = data/characters/<id>.json（名字、职业、贴图集、技能表、成长线）+ scripts/characters/<id>.gd（行为）。
## 博士（受击体、移动、拾取、等级、经验）由 game.gd + characters/doctor.gd 持有，干员通过 g 读写。
extends RefCounted

const A = preload("res://scripts/art.gd")

var g                      # Game (Node2D)
var def: Dictionary = {}   # 角色定义（JSON）
var id := ""
var cls := ""              # 职业：先锋/近卫/重装/狙击/术师/医疗/辅助/特种（def.class）

# ---- 场上实体：位置 / 朝向 / 移动（squad.gd 每帧调 follow）
var pos := Vector2.INF
var face := 1.0
var mv := 0.0              # 平滑后的移动速度（切换跑步动画用）
var mt := 0.0              # 移动计时（跑步循环）
var slot := 0              # 编队位序号
var elite := 0             # 精英化阶段 0 / 1 / 2
var prog := 0              # 已应用的成长节点数（progression 数组下标）
var sp: Array = [0.0, 0.0, 0.0]   # 三个自动技能的充能（契约 v2.1：招募 S1 / 精一 S2 / 精二 S3）
var cur_skill := 0                # 正在起手的技能序号（start_skill → _release_skill）
var rej: Dictionary = {}          # 排异反应：被海嗣化的技能序号 → true
var perm: Array = [false, false, false]   # 永久型技能（JSON permanent）：充能一次释放后永久生效，不再充能
var attack_t := 0.0        # >0 表示正在播放攻击动作（由干员在出手时设置）
var attack_dur := 0.25
var fire_t := -1.0         # 出手帧倒计时（start_attack / start_skill 后到点调用 _release / _release_skill）
var act_kind := "attack"   # 当前动作条：attack / skill
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
			elif sk[i].get("mode", "auto") != "auto":
				push_error("干员 %s 的技能 %d 必须是 auto（手动技能只属于博士）" % [cid, i + 1])
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


## 手动技能入口（Space / J）：三自动角色返回 false；两自动一主动的角色在这里校验解锁与资源后施放
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
func charge_skills(dt: float) -> int:
	var ready := -1
	for i in 3:
		if not skill_unlocked(i):
			continue
		var need := sp_need(i)
		if need <= 0.0 or skill_active_left(i) > 0.0 or perm[i]:
			continue
		if sp[i] < need:
			sp[i] = minf(need, sp[i] + dt * g.sp_mult * stat(&"op_skill_sp") * g._lamp_sp())
		if sp[i] >= need:
			ready = i
	return ready


## 消费技能 i 的充能并通知藏品（技能开始事件）
func spend_sp(i: int) -> void:
	sp[i] = 0.0
	if skill_def(i).get("permanent", false):
		perm[i] = true
		sp[i] = sp_need(i)
	g.rfx.on_skill_start()


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


## 排异反应（结局四）：随机一个已解锁、未海嗣化的技能被海嗣化——技能强度 +40%、充能需求 +30%，博士最大生命 -10
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
	g._sync_stats()
	g.hp = minf(g.hp, g.max_hp)
	return "%s「%s」海嗣化：技能强度 +40%%、充能 +30%%；博士最大生命 -10" % [display_name(), skill_def(i).get("name", "")]


## 精英化演出：新技能（+ 精一天赋）
func _elite_show(stage: int) -> void:
	var items: Array = [g._skill_item(self, stage)]
	var td := talent_def()
	if stage == 1 and not td.is_empty():
		items.append({"tag": "天赋", "tag_en": "TALENT", "glyph": td.get("name", "赋").substr(0, 1), "name": td.get("name", ""), "desc": td.get("desc", ""), "col": col().lerp(Color(1, 1, 1), 0.3)})
	g.show_queue.append({"head": "%s · 精英化%s" % [display_name(), ["", "一", "二"][stage]], "en": "ELITE  PROMOTION  " + ["", "I", "II"][stage], "col": col(), "op": self, "items": items})


# ---------------------------------------------------------------- 干员特效粒子（docs/25）

## 加一个粒子：kind / pos / life 必填；col、r、vel、drag、grav、ang、floor（地面层）按 kind 取用
func fx(f: Dictionary) -> void:
	f["max"] = f.life
	pfx.append(f)


func _tick_pfx(dt: float) -> void:
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
				# 地裂：从中心放射的暗线 + 亮芯
				var k3: float = 1.0 - a
				var n: int = f.get("n", 8)
				for q in n:
					var dv := Vector2.from_angle(q * TAU / n + f.get("ang", 0.0))
					var l: float = f.r * (0.35 + 0.65 * minf(1.0, k3 * 3.0))
					g.draw_line(f.pos + dv * 6.0, f.pos + dv * l, Color(0.03, 0.02, 0.02, 0.85 * a), 3.0)
					g.draw_line(f.pos + dv * 6.0, f.pos + dv * l * 0.75, Color(c.r * 1.7, c.g * 1.5, c.b, a), 1.5)


## 子类的自定义粒子；返回 true 表示已绘制
func _draw_pfx(_f: Dictionary, _a: float) -> bool:
	return false


## 一圈火花
func fx_sparks(p: Vector2, c: Color, n: int, spd: float, life := 0.4, sz := 3.0, grav := 0.0, floor_layer := false) -> void:
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


## 本干员命中的作用域（docs/23 §5）
func scopes() -> Array:
	return ["class:" + cls, "op:" + id]


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
			g._sync_stats()
		"elite":
			elite = int(n.level)
			on_elite(elite, choice)
			_elite_show(elite)
		"custom":
			on_custom_node(n.get("id", ""), choice)
	if n.has("banner"):
		g._show_banner(n.banner % display_name() if "%s" in n.banner else n.banner)


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

## 跟随博士的编队位：近处慢慢挪、远处快步跟上；离得太远（开局 / 传送）直接归位
func follow(dt: float, target: Vector2) -> void:
	if pos == Vector2.INF or pos.distance_to(target) > 700.0:
		pos = target
		mv = 0.0
		return
	var prev: Vector2 = pos
	target = follow_target(target)
	var d: float = pos.distance_to(target)
	var k: float = clampf(dt * (3.0 if d < 20.0 else 6.0), 0.0, 1.0)
	pos = pos.lerp(target, k)
	if g.tex.get("prop_pillar") != null:
		pos = g.map.push_out(pos, 10.0)
	var vel: Vector2 = (pos - prev) / maxf(dt, 0.0001)
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
	if attack_t > 0.0 and anim_tex(act_kind) != null:
		want = act_kind
	elif mv > 30.0 and anim_tex("run") != null:
		want = "run"
	if want != anim_kind:
		anim_kind = want
		anim_t = 0.0
	anim_t += dt


## 起手：面向目标、播攻击条（4 帧 8fps 约定：0.5 秒，零基第 2 帧出手）；没有攻击条就立即出手
## 贴图槽带 fps + fire（出手帧，零基）时，时长与出手时刻按帧条算，dur / fire_at 参数被忽略（docs/24 §1）
func start_attack(aim: Vector2, dur: float = 0.5, fire_at: float = 0.25) -> void:
	_start_action("attack", aim, dur, fire_at)


## 起手技能动作（skill 帧条）；idx 为技能序号（默认沿用 cur_skill）；没有 skill 条时直接出手
func start_skill(aim: Vector2, idx: int = -1, dur: float = 0.6, fire_at: float = 0.3) -> void:
	if idx >= 0:
		cur_skill = idx
		spend_sp(idx)
	_start_action("skill", aim, dur, fire_at)


func _start_action(kind: String, aim: Vector2, dur: float, fire_at: float) -> void:
	if aim != Vector2.INF and absf(aim.x - pos.x) > 2.0:
		face = signf(aim.x - pos.x)
	act_kind = kind
	if anim_tex(kind) == null:
		if kind == "skill":
			_release_skill()
		else:
			_release()
		return
	var spec := sprite_spec(kind)
	if spec.has("fps") and spec.has("fire"):
		var n := float(spec.get("frames", anim_hframes(anim_tex(kind), kind)))
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


## 跟随目标点：默认是编队位；近战干员可以改成"前压到敌人身边"（离博士不超过 leash）
func follow_target(slot_pos: Vector2) -> Vector2:
	return slot_pos


## 近战前压：博士 leash 范围内最近的敌人；返回站位点（敌人身前 gap 处）或 INF
func melee_spot(leash: float, gap: float) -> Vector2:
	var ts: Array = g._nearest(1, leash, g.ppos)
	if ts.is_empty():
		return Vector2.INF
	var e: Dictionary = ts[0]
	var d: Vector2 = pos - e.pos
	if d.length() < 1.0:
		d = Vector2(-face, 0)
	return e.pos + d.normalized() * (gap + e.r)


## 召唤物等附属实体：参与 2.5D 排序的条目 [{"y": 脚底 y, …}]，由 draw_extra 绘制
func extra_bodies() -> Array:
	return []


func draw_extra(_it: Dictionary) -> void:
	pass


func draw_extra_shadows() -> void:
	pass


## 近战扇形命中：对 origin 周围 radius、朝 ang ±half 的敌人造成伤害；返回命中的敌人
func melee_hit(src: String, origin: Vector2, ang: float, half: float, radius: float, dmg: float, kb := 0.0, stun := 0.0, tags: Array = []) -> Array:
	var hits: Array = g._arc_hit(origin, ang, half, radius)
	for e in hits:
		g._hit(src, tags)
		g._damage(e, dmg)
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
	g._draw_sprite_at(pos, st.flip, Color.WHITE, st.frame, st.tex, st.hf, foot_off(st.tex, st.get("kind", "")))


## 在别处画一份当前帧（分身 / 残影）
func draw_body_at(p: Vector2, flip: bool, col: Color, st: Dictionary = {}) -> void:
	if st.is_empty():
		st = anim_state()
	if st.is_empty():
		return
	g._draw_sprite_at(p, flip, col, st.frame, st.tex, st.hf, foot_off(st.tex, st.get("kind", "")))
