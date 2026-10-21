## 编队干员的基类（docs/23）：开局干员是玩家操控的主控（唯一受击体，生命 / 减伤 / 法抗见 JSON leader 段），
## 招募的干员跟随主控、自动输出、不会倒下；定义 game.gd / squad.gd 调用的接口，默认实现为空。
## 每个干员 = data/characters/<id>.json（名字、职业、贴图集、技能表、成长线）+ scripts/characters/<id>.gd（行为）。
## 生命、等级、经验、拾取由 game.gd 持有；博士是挂件（characters/doctor.gd：指挥技能、被动、排异反应）。
## 干员调用 game.gd 的能力一律走 op_api.gd（本类的父类），不直接调用 g._ 开头的内部函数。
extends "res://scripts/characters/op_api.gd"

const GroundCrack = preload("res://scripts/render/ground_crack.gd")   # 地裂共用画法
const A = preload("res://scripts/art.gd")
const OperatorContract = preload("res://scripts/characters/operator_contract.gd")   # 帧条 / 动画数据契约（docs/108 §10）
## B6 ②（docs/101 §7.3.6）：积木按定义所在的 blocks 文件直连（原 const OpBlocks = preload(op_blocks.gd) 门面）
## 发版排查（10-16，bisect 到 dada5e32）：blocks 24 个文件是一条单继承链（ob_geom → ob_core → ob_check → … → seg_angelina → … → seg_skalter），
## 链上任一文件都transitively 带出它之前的全部文件；这里原来对 ob_check.gd / seg_angelina.gd 各开一次 preload，两条路径在
## character.gd 自己的编译期同时解析同一条链（seg_angelina 更靠后，ob_check 是它的祖先），Godot 退出时报 resources still in use
## （verbose 下指向 enemy_db / balance / data / art / look 这些被 blocks 间接 preload 的文件；--quit 复测确认改这里能稳定消除）。
## 只真正 preload 链上最靠后的那个（SegAngelina 已经包含 ObCheck 的 validate），ObCheck 改成别名，不再单开一条路径
const SegAngelina = preload("res://scripts/characters/blocks/seg_angelina.gd")
const ObCheck = SegAngelina
const Dc = preload("res://scripts/render/declutter.gd")   # render/hit_rings：攻击 / 技能命中的装饰圆圈开关

var def: Dictionary = {}   # 角色定义（JSON）
var id := ""
var cls := ""              # 职业：先锋/近卫/重装/狙击/术师/医疗/辅助/特种（def.class）
var op_key := ""          # "op:" + id

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
var route := ""            # 培养路线 id（docs/119 §4.1：节点 4 二选一时记下；节点 5 / 6、卡面、统计按它解析；"" = 未选 / 不分支）
const BranchBal = preload("res://scripts/core/balance.gd")
var sp: Array = [0.0, 0.0, 0.0]   # 三个自动技能的充能（契约 v2.1：招募 S1 / 精一 S2 / 精二 S3）
var cur_skill := 0                # 正在起手的技能序号（start_skill → _release_skill）
var rej: Dictionary = {}          # 排异反应：被海嗣化的技能序号 → true
var perm: Array = [false, false, false]   # 永久型技能（JSON permanent）：充能一次释放后永久生效，不再充能
var attack_t := 0.0        # >0 表示正在播放攻击动作（由干员在出手时设置）
var attack_dur := 0.25
var attack_fire_at := 0.0
var attack_phased := false
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
	op_key = "op:" + id   # 本人作用域键（stats 的 scope），每帧拼接的省掉（docs/101 S9）


static func list_ids() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://data/characters")
	if d != null:
		for f in d.get_files():
			if f.ends_with(".json"):
				out.append(f.get_basename())
	return out


static func load_def(cid: String) -> Dictionary:
	var f := FileAccess.open(def_path(cid), FileAccess.READ)
	if f == null:
		push_error("character def missing: " + cid)
		return {"id": cid}
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return {"id": cid}
	# 测试旋钮（docs/88）：--bal=opbase/<id>/<base 键>=值 覆盖干员 JSON 的 base 段（含数据干员 "$键" 引用）；
	# 只在命令行带 --bal 时才有这一段（Bal 只在 debug 构建读命令行），正式游玩与发布版不受影响
	var ob: Dictionary = preload("res://scripts/core/balance.gd").sec("opbase/" + cid)
	if not ob.is_empty() and d.get("base") is Dictionary:
		for k in ob:
			d.base[k] = ob[k]
	fill_text(d, d.get("base", {}) if d.get("base") is Dictionary else {})
	return d


## 玩家可见文字里的数值占位（docs/61 §1.4）：desc / banner 里的「{表达式}」按 base 求值后填进去。
## 表达式至少引用一个 $键，支持数字、+ - * / 与括号，例如 {$s1_mult}、{$e1_per*100}%、{$n2_mult*100-100}%、{(1-$slow)*100}%；末尾 :N 指定小数位（{$a*$b:0}）；
## 结果按 text_fmt 去掉多余的小数（最多 3 位）。填在 load_def 里：选人 / 图鉴 / 升级卡 / 精英化演出 / 属性面板读到的都是填好的文字，
## 改 base 数值（含 --bal=opbase）文字自动跟着变。求不出值的占位原样留下并报错（tools/op_text_check.py 同规则静态检查）
const TEXT_FILL_KEYS := ["desc", "banner"]


static func fill_text(n, base: Dictionary) -> void:
	if n is Dictionary:
		for k in n:
			if k == "base" or k == "_doc":
				continue
			var v = n[k]
			if v is String and k in TEXT_FILL_KEYS and v.contains("{"):
				n[k] = fill_line(v, base)
			elif v is Dictionary or v is Array:
				fill_text(v, base)
	elif n is Array:
		for v in n:
			if v is Dictionary or v is Array:
				fill_text(v, base)


## 一行文字里的全部 {…$键…} 占位换成数值
static func fill_line(s: String, base: Dictionary) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		var a := s.find("{", i)
		if a < 0:
			break
		var b := s.find("}", a + 1)
		if b < 0:
			break
		var expr := s.substr(a + 1, b - a - 1)
		out += s.substr(i, a - i)
		if expr.contains("$"):
			var nd := 3
			var ci := expr.rfind(":")
			if ci > 0 and expr.substr(ci + 1).is_valid_int():   # {表达式:N}：四舍五入到 N 位小数（150.15 → {…:0} → 150）
				nd = clampi(expr.substr(ci + 1).to_int(), 0, 3)
				expr = expr.substr(0, ci)
			var r := text_eval(expr, base)
			if r[0]:
				out += text_fmt(r[1], nd)
			else:
				push_error("干员文字占位「{%s}」求值失败：%s" % [expr, r[2]])
				out += s.substr(a, b - a + 1)
		else:
			out += "{" + expr + "}"
		i = b + 1
	return out + s.substr(i)


## 去掉多余的小数：最多保留 nd 位（缺省 3：0.15 → 0.15，1.50 → 1.5，15.0 → 15，1.275 → 1.275）
static func text_fmt(v: float, nd := 3) -> String:
	var k := pow(10.0, nd)
	var r := floorf(v * k + 0.5) / k   # 与 tools/op_text_check.py 同算法（.5 进位）
	if absf(r - roundf(r)) < 0.0001:
		return str(int(roundf(r)))
	var t := ("%." + str(nd) + "f") % r
	while t.ends_with("0"):
		t = t.left(-1)
	return t


## 文字占位的表达式求值：[ok, 值, 错误说明]；递归下降（加减 < 乘除 < 负号 / 括号）
static func text_eval(expr: String, base: Dictionary) -> Array:
	var toks: Array = []
	var s := expr.replace(" ", "")
	var i := 0
	while i < s.length():
		var c := s[i]
		if c in "+-*/()":
			toks.append(c)
			i += 1
		elif c == "$" or c.is_valid_int() or c == ".":
			var j := i + 1
			while j < s.length() and not (s[j] in "+-*/()"):
				j += 1
			toks.append(s.substr(i, j - i))
			i = j
		else:
			return [false, 0.0, "看不懂的字符「%s」" % c]
	var st := {"t": toks, "i": 0, "err": ""}
	var v := _te_sum(st, base)
	if st.err == "" and int(st.i) != toks.size():
		st.err = "多余的「%s」" % str(toks[st.i])
	return [st.err == "", v, st.err]


static func _te_sum(st: Dictionary, base: Dictionary) -> float:
	var v := _te_prod(st, base)
	while st.err == "" and int(st.i) < st.t.size() and st.t[st.i] in ["+", "-"]:
		var op: String = st.t[st.i]
		st.i += 1
		var r := _te_prod(st, base)
		v = v + r if op == "+" else v - r
	return v


static func _te_prod(st: Dictionary, base: Dictionary) -> float:
	var v := _te_atom(st, base)
	while st.err == "" and int(st.i) < st.t.size() and st.t[st.i] in ["*", "/"]:
		var op: String = st.t[st.i]
		st.i += 1
		var r := _te_atom(st, base)
		if op == "*":
			v *= r
		elif r == 0.0:
			st.err = "除以 0"
		else:
			v /= r
	return v


static func _te_atom(st: Dictionary, base: Dictionary) -> float:
	if int(st.i) >= st.t.size():
		st.err = "表达式不完整"
		return 0.0
	var t: String = st.t[st.i]
	st.i += 1
	if t == "-":
		return -_te_atom(st, base)
	if t == "(":
		var v := _te_sum(st, base)
		if int(st.i) >= st.t.size() or st.t[st.i] != ")":
			st.err = "缺「)」"
			return 0.0
		st.i += 1
		return v
	if t.begins_with("$"):
		var k := t.substr(1)
		if not base.has(k) or not (base[k] is int or base[k] is float):
			st.err = "base 里没有数字「%s」" % k
			return 0.0
		return float(base[k])
	if t.is_valid_float():
		return t.to_float()
	st.err = "看不懂的「%s」" % t
	return 0.0


## 测试专用干员（docs/61 §测试）：不在 data/characters/ 里（不进名单 / 招募池 / 图鉴），只能用 --op=<id> 指名加载
const TEST_OPS_DIR := "res://tests/data_ops/"


## 干员定义文件：data/characters/<id>.json；没有时找测试专用干员
static func def_path(cid: String) -> String:
	var p := "res://data/characters/%s.json" % cid
	if not FileAccess.file_exists(p) and FileAccess.file_exists(TEST_OPS_DIR + cid + ".json"):
		return TEST_OPS_DIR + cid + ".json"
	return p


## 能按 id 加载（正式名单 + 测试专用干员）
static func exists(cid: String) -> bool:
	return cid != "" and FileAccess.file_exists(def_path(cid))


## 按 id 实例化角色（脚本路径来自定义里的 script 字段，默认 scripts/characters/<id>.gd；
## 有 blocks 而没写 script 的是数据干员，用 data_operator.gd，docs/61）。
## 测试开关 --opscript=<id>=<脚本路径>：同一个 id 改用别的脚本加载（积木等价测试用手写参照，tools/check.py blocks_eq）
static func create(game, cid: String) -> RefCounted:
	var d := load_def(cid)
	var path: String = d.get("script", "res://scripts/characters/data_operator.gd" if d.has("blocks") else "res://scripts/characters/%s.gd" % cid)
	for a in (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()):   # 发布版不读命令行（check_release）；Cfg 在测试场景可能未加载，同 balance.gd 写法
		if a.begins_with("--opscript=%s=" % cid):
			path = a.substr(("--opscript=%s=" % cid).length())
	var scr = load(path)
	if scr == null:
		push_error("character script missing: " + path)
		return null
	var inst = scr.new(game, d)
	if validate_on():
		validate_operator(cid, d)
	return inst


## 招募时的干员 / 积木校验（约 2500 行，只读、只报错）：只在 debug 构建（编辑器、快检、批跑）跑，发布版每次招募不再跑（docs/101 S8）。
## --novalidate：debug 下也跳过，用来对照校验没有副作用（同 seed TRACE 逐行相同）。JSON 的正确性由快检 core / 各积木测试保证
static func validate_on() -> bool:
	return OS.is_debug_build() and not OS.get_cmdline_user_args().has("--novalidate")


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
	if d.get("sprites", {}).has("skill_pose"):
		push_error("干员 %s 的 sprites.skill_pose 已移除，请按 docs/105 §4 迁移到 sprites.skills" % cid)
		ok = false
	# 帧条 / 动画数据契约 V1–V9（docs/108 §10：attack_timing、frame_durations、画布与 foot、native_motion、逐帧点、extra_sprites）
	for contract_error in OperatorContract.errors(d):
		push_error("干员 %s：%s" % [cid, contract_error])
		ok = false
	# 多条技能帧条（sprites.skills，docs/87 §3.5）：键 s1–s3，引用的帧条要在 sprites 里，非主动作的要列进 extra_sprites
	var sq_ = d.get("sprites", {}).get("skills", null)
	if sq_ != null:
		if not (sq_ is Dictionary):
			push_error("干员 %s 的 sprites.skills 须是字典" % cid)
			ok = false
		else:
			for sk_ in sq_:
				if str(sk_).begins_with("_"):
					continue   # _doc
				var q = sq_[sk_]
				if not str(sk_) in ["s1", "s2", "s3"] or not (q is Dictionary):
					push_error("干员 %s 的 sprites.skills 键「%s」须是 s1 / s2 / s3 且值为字典" % [cid, sk_])
					ok = false
					continue
				if not (q.has("anim") or q.has("hold") or q.has("start")):
					push_error("干员 %s 的 sprites.skills.%s 要有 anim、hold 或 start" % [cid, sk_])
					ok = false
				if q.has("hold") and not q.has("intro"):
					push_error("干员 %s 的 sprites.skills.%s 有 hold 就要有 intro" % [cid, sk_])
					ok = false
				if q.has("hold") and q.has("start"):
					push_error("干员 %s 的 sprites.skills.%s 不能同时写 hold 与 start" % [cid, sk_])
					ok = false
				if q.has("anim") and ["intro", "hold", "start", "enter", "loop", "run", "attack", "end"].any(func(key): return q.has(key)):
					push_error("干员 %s 的 sprites.skills.%s 单条 anim 不能混写序列字段" % [cid, sk_])
					ok = false
				if q.has("start") and not q.has("loop"):
					push_error("干员 %s 的 sprites.skills.%s 有 start 就要有 loop" % [cid, sk_])
					ok = false
				if (q.has("attack") or q.has("run") or q.has("enter")) and (not q.has("loop") or not q.has("start") or q.has("hold")):
					push_error("干员 %s 的 sprites.skills.%s 的 attack / run / enter 槽需要 start 与 loop，不能用于 hold" % [cid, sk_])
					ok = false
				for key in ["shadow", "shadow_a"]:
					if q.has(key) and (not (q[key] is float or q[key] is int) or not is_finite(float(q[key])) or float(q[key]) < 0.0 or float(q[key]) > 1.0):
						push_error("干员 %s 的 sprites.skills.%s.%s 须为 0–1 的数值" % [cid, sk_, key])
						ok = false
				for part in ["anim", "intro", "hold", "start", "enter", "loop", "run", "end", "attack"]:
					if not q.has(part):
						continue
					var seg = q[part]
					if part == "attack" and seg is Dictionary:
						push_error("干员 %s 的 sprites.skills.%s.attack 须是帧条名（出手帧按该条 fire）" % [cid, sk_])
						ok = false
						continue
					if seg is Dictionary and seg.has("reverse") and not (seg.reverse is bool):
						push_error("干员 %s 的 sprites.skills.%s.%s.reverse 须是布尔值" % [cid, sk_, part])
						ok = false
					var k := seq_anim(seg)
					if k == "" or not d.sprites.has(k) or not (d.sprites[k] is Dictionary) or not d.sprites[k].has("tex"):
						push_error("干员 %s 的 sprites.skills.%s.%s 帧条「%s」不在 sprites（须是带 tex 的槽）" % [cid, sk_, part, k])
						ok = false
					elif not k in ["idle", "run", "attack", "skill", "hurt", "death"] and not k in d.get("extra_sprites", []):
						push_error("干员 %s 的 sprites.skills.%s.%s 帧条「%s」没列进 extra_sprites" % [cid, sk_, part, k])
						ok = false
					elif seg is Dictionary and seg.has("frames"):
						var nf = d.sprites[k].get("frames", null)
						if not (seg.frames is Array) or seg.frames.is_empty() or seg.frames.any(func(x): return not (x is float or x is int) or float(x) != float(int(x)) or int(x) < 0 or (nf != null and int(x) >= int(nf))):
							push_error("干员 %s 的 sprites.skills.%s.%s.frames 须是帧条范围内的帧号数组" % [cid, sk_, part])
							ok = false
	for visual_error in preload("res://scripts/characters/summon_visual.gd").errors(d.get("sprites", {}), d.get("extra_sprites", [])):
		push_error("%s: %s" % [cid, visual_error])
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
	var fac = d.get("faction", [])
	if not (fac is Array) or fac.any(func(x): return not (x is String) or x == ""):
		push_error("干员 %s 的 faction 必须是字符串数组" % cid)
		ok = false
	# 数据干员（docs/61 §8）：积木名、参数、$ 引用、伤害来源、节点对应
	if d.has("blocks") and not ObCheck.validate(cid, d):
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
			sp[i] = minf(need, sp[i] + dt * g.sp_mult * stat(&"op_skill_sp") * lamp_sp() * (0.0 if g.apop_t > 0.0 else 1.0))   # 凋亡损伤满条：自然充能暂停（combat.add_apop）
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
	if i < 0:
		return false
	var a = skill_def(i).get("aim", false)
	return a is String or (a is bool and a)


## 选落点（契约 v2.5）：技能 JSON "aim": "point" —— 玩家直接给落点（鼠标光标 / 键盘按住蓄距离 / 右摇杆推量 / 触屏拖动距离，
## 见 doctor.point_now），落点夹在 aim_range 内，不吸附、不看密度（干员 base aim_snap > 0 时才吸附）。
## 给点时 dir 取主控指向落点的方向，照走「带方向」那一套判定（manual_ready / manual_block_reason）
func manual_point(i: int) -> bool:
	return i >= 0 and str(skill_def(i).get("aim", "")) == "point"


## 选落点技能的最远距离（干员 base aim_range，缺省 400，吃射程加成）
func aim_range(_i: int) -> float:
	return base("aim_range", 400.0) * stat(&"op_range")


## 把玩家给的点夹进 aim_range
func clamp_point(i: int, pt: Vector2) -> Vector2:
	var off: Vector2 = pt - pos
	return pos + off.limit_length(aim_range(i))


var manual_dir := Vector2.ZERO
var manual_pt := Vector2.INF   # 选落点技能：玩家给的落点（已夹进 aim_range；出手帧读，读完置 INF）

## 播一次性音效（音量取 sfx.gd 里的常量名）。本文件也被 -s 测试脚本直接加载，那时没有 Sfx 自动加载，按节点路径取
func _sfx_play(name: String, vol_const: String, pitch_var: float) -> void:
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g != null and g.is_inside_tree() else null
	if sfx != null:
		var vol: float = sfx.ULP_RELEASE_DB if vol_const == "ULP_RELEASE_DB" else sfx.ATK_GATE_DB
		sfx.play(name, vol, 1.0, pitch_var)


func cast_manual(i: int, dir: Vector2 = Vector2.ZERO, pt: Vector2 = Vector2.INF) -> bool:
	if not manual_aims(i):
		dir = Vector2.ZERO
	if manual_point(i) and pt != Vector2.INF and pos != Vector2.INF:
		pt = clamp_point(i, pt)
		dir = (pt - pos).normalized() if pt.distance_to(pos) > 1.0 else Vector2(face, 0.0)
	else:
		pt = Vector2.INF
	if not manual_ready(i, dir):
		return false
	manual_buf = 0.0
	manual_dir = dir.normalized() if dir != Vector2.ZERO else Vector2.ZERO
	manual_pt = pt
	start_skill(pt if pt != Vector2.INF else (pos + manual_dir * 60.0 if manual_dir != Vector2.ZERO else Vector2.INF), i)
	if pt != Vector2.INF:
		_sfx_play("ulp_release", "ULP_RELEASE_DB", 0.0)   # 选落点技能放出（键盘蓄力 / 鼠标 / 摇杆 / 触屏都响）
	return true


## 技能 i 放出后还有没打完的次数型效果（维什戴尔 / 艾雅法拉 S1「接下来 3 发强化」）：skill_active_left 管的是持续时间，
## 这类按发数算的效果它恒为 0。图鉴演示用它判断这一段还没演完（run/demo.gd），干员按需重写
func skill_pending(_i: int) -> bool:
	return false


## 预计落点（瞄准指示用）：dir 同上；干员没实现或此刻没有落点返回 Vector2.INF
func manual_aim_point(_i: int, _dir: Vector2 = Vector2.ZERO) -> Vector2:
	return Vector2.INF


## 玩家按下手动技能键（doctor.try_manual_skill 调用）：就绪就放；充能已满、只是正在出手（或干员自己的「稍等」条件，
## manual_block_reason 返回空串）时先记下这次按键（连同方向），MANUAL_BUF 秒内一满足就放，免得按键撞上出手被吞。
## 返回 "" = 已放出或已记下；否则返回提示原因
const MANUAL_BUF := 1.0
var manual_buf := 0.0
var manual_buf_dir := Vector2.ZERO
var manual_buf_pt := Vector2.INF

func press_manual(i: int, dir: Vector2 = Vector2.ZERO, pt: Vector2 = Vector2.INF) -> String:
	if not manual_aims(i):
		dir = Vector2.ZERO
	if cast_manual(i, dir, pt):
		return ""
	if manual_point(i) and pt != Vector2.INF and pos != Vector2.INF and pt.distance_to(pos) > 1.0:
		dir = (pt - pos).normalized()
	if skill_active_left(i) > 0.0:
		return "生效中"
	if has_method("away") and call("away"):
		return "暂时离场"
	if sp[i] < sp_need(i):
		return "技力不足"
	var why := manual_block_reason(i, dir)
	if why == "":
		manual_buf = MANUAL_BUF
		manual_buf_dir = dir
		manual_buf_pt = pt
	return why


func _tick_manual_buf(dt: float) -> void:
	if manual_buf <= 0.0:
		return
	manual_buf -= dt
	var i := manual_index()
	if i < 0:
		manual_buf = 0.0
	elif manual_ready(i, manual_buf_dir):
		cast_manual(i, manual_buf_dir, manual_buf_pt)


## 充能已满但干员自己的条件不满足、等也没用时，按键提示的原因（如「附近没有敌人」）；空串 = 只是稍等，按键先记下
func manual_block_reason(_i: int, _dir: Vector2 = Vector2.ZERO) -> String:
	return ""


## 机器人（自动测试 / 批跑）是否替玩家按下手动技能 i：已就绪时每帧询问。缺省按保命型：主控生命低于
## balance.json bot/manual_hp（0.3）才按；进攻型手动技能重写成自己的时机（乌尔比安 S3：就绪即放）
func bot_wants_manual(_i: int) -> bool:
	return g.hp < g.max_hp * preload("res://scripts/core/balance.gd").v("bot/manual_hp", 0.3)


# ---------------------------------------------------------------- 手动普攻（契约 v2.5，docs/26 §v2.5）

## 设置「普通攻击：手动」时只管主控（g.doctor.manual_attack 已排除机器人 / 自动测试 / 图鉴演示）：没按攻击键不起手，冷却照走，
## 一按就出；轻点先记下 manual/atk_buf 秒（冷却没转好时不白按），按住连发。瞄准方向见 doctor.attack_dir。干员分两类接：
## A 方向类（atk_point / atk_angle）：严格沿瞄准方向打，前方没人照样出手；B 需要目标类（attack_targets / aim_targets）：
## 瞄准方向 ±manual/aim_cone_deg（45°）内最近的，没有退到 ±manual/aim_fallback_deg（90°，前半面），都没有才不出手、保留冷却
func manual_attack() -> bool:
	return is_leader and g.doctor.manual_attack


## 这一帧允许普攻起手（自动模式恒为真）
func attack_gate() -> bool:
	return not manual_attack() or g.doctor.attack_want()


## 没起手时的重试间隔：手动且没按攻击键时为 0（按下当帧就出），否则原值
func idle_cd(v: float) -> float:
	return 0.0 if manual_attack() and not g.doctor.attack_want() else v


var atk_aim := Vector2.ZERO    # A 类：这一击手动给的方向（起手时记下，出手帧 atk_angle 用）；ZERO = 自动

## A 类起手点：ts 为自动选出的目标（nearest_enemies 结果），reach 为这一击的距离。返回起手朝向点，Vector2.INF = 这一帧不出手。
## 自动：有目标打目标；手动：没按不出，按了沿瞄准方向（触屏不拖 = 退回自动目标）
func atk_point(ts: Array, reach: float) -> Vector2:
	atk_aim = Vector2.ZERO
	if manual_attack():
		if not g.doctor.attack_want():
			return Vector2.INF
		var d: Vector2 = g.doctor.attack_dir()
		if d != Vector2.ZERO:
			atk_aim = d
			g.doctor.atk_buf = 0.0
			return pos + d * reach
		if not ts.is_empty():
			g.doctor.atk_buf = 0.0
	return ts[0].pos if not ts.is_empty() else Vector2.INF


## A 类出手帧的方向角：这一击手动给了方向就用它（并转身），否则用 fallback（干员原来按目标算的角）
func atk_angle(fallback: float) -> float:
	if atk_aim == Vector2.ZERO:
		return fallback
	var a: float = atk_aim.angle()
	face_to(a)
	return a


## A 类里的远程落点（维什戴尔炮弹、艾雅法拉熔岩弹）：这一击手动给了方向时，落点在瞄准方向上、距离 = 方向 ±aim_cone_deg 内
## 最近敌人的距离；锥内没人取 reach × manual/land_empty（0.8）。返回伪目标 {id: -1, pos}（只有 pos / id 可用）；自动时返回空字典
func aim_land(reach: float) -> Dictionary:
	if atk_aim == Vector2.ZERO:
		return {}
	var BalS = preload("res://scripts/core/balance.gd")
	var c: float = cos(deg_to_rad(BalS.v("manual/aim_cone_deg", 45.0))) - 0.0001
	var dist: float = reach * BalS.v("manual/land_empty", 0.8)
	for e in nearest_raw(48, reach, pos):
		var off: Vector2 = e.pos - pos
		if off.length() >= 1.0 and off.normalized().dot(atk_aim) >= c:
			dist = off.length()
			break
	return {"id": -1, "pos": pos + atk_aim * dist, "dead": false, "elite": false, "boss": false, "r": 0.0}


## B 类起手选目标：自动 = nearest_enemies；手动没按 = 空；按了 = aim_targets
func attack_targets(n: int, max_dist: float, origin: Vector2 = Vector2.INF) -> Array:
	if not manual_attack():
		return nearest_enemies(n, max_dist, origin)
	if not g.doctor.attack_want():
		return []
	var out := aim_targets(n, max_dist, origin)
	if not out.is_empty():
		g.doctor.atk_buf = 0.0
	elif g.doctor.atk_edge:
		_sfx_play("atk_gate", "ATK_GATE_DB", 0.05)   # 按了但前方没敌人、不出手：轻「咔」（只在按下那一帧）
	return out


## B 类按瞄准方向选目标（出手帧重新找目标也用它；不看按键，起手后松手照样打完）：
## ±aim_cone_deg 内由近到远，没有退到 ±aim_fallback_deg；触屏不拖（方向为 ZERO）= 最近的
func aim_targets(n: int, max_dist: float, origin: Vector2 = Vector2.INF) -> Array:
	if not manual_attack():
		return nearest_enemies(n, max_dist, origin)
	var d: Vector2 = g.doctor.attack_dir()
	if d == Vector2.ZERO:
		return nearest_enemies(n, max_dist, origin)
	var BalS = preload("res://scripts/core/balance.gd")
	var o: Vector2 = g.ppos if origin == Vector2.INF else origin
	var pool: Array = nearest_raw(maxi(n * 4, 48), max_dist, origin)
	for deg in [BalS.v("manual/aim_cone_deg", 45.0), BalS.v("manual/aim_fallback_deg", 90.0)]:
		var c: float = cos(deg_to_rad(deg)) - 0.0001
		var out: Array = []
		for e in pool:
			var off: Vector2 = e.pos - o
			if off.length() < 1.0 or off.normalized().dot(d) >= c:
				out.append(e)
				if out.size() >= n:
					break
		if not out.is_empty():
			return out
	return []


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
	if g.get("telemetry") != null:
		g.telemetry.on_cast(id)   # 作战记录：技能发动次数（docs/77）


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


## 排异反应（深蓝之心线）：随机一个已解锁、未海嗣化的技能被海嗣化——技能强度 +40%、充能需求 +30%，主控最大生命 -10
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
	return "%s「%s」海嗣化：技能强度 +40%%、所需技力 +30%%；队长最大生命 -10" % [display_name(), skill_def(i).get("name", "")]


## 解除一个排异反应（docs/57 P18）：撤销那次排异加的属性来源。没有排异时返回 false
func clear_rejection() -> bool:
	if rej.is_empty():
		return false
	var i: int = rej.keys()[0]
	rej.erase(i)
	g.stats.remove_source("rej:%s:%d" % [id, i])
	refresh_stats()
	return true


## 精英化演出：新技能（+ 精一天赋）
func _elite_show(stage: int) -> void:
	var items: Array = [skill_item(stage)]
	var td := talent_def()
	if stage == 1 and not td.is_empty():
		items.append({"tag": "天赋", "tag_en": "TALENT", "glyph": td.get("name", "赋").substr(0, 1), "name": td.get("name", ""), "desc": td.get("desc", ""), "col": col().lerp(Color(1, 1, 1), 0.3)})
	# 普攻形态（docs/91 §0.5）：精英化节点写了 attack {name, desc} 时，天赋后面再加一张「普攻」卡
	for n in progression():
		if n is Dictionary and n.get("type", "") == "elite" and int(n.get("level", 0)) == stage and n.get("attack", null) is Dictionary:
			var ak: Dictionary = n.attack
			items.append({"tag": "普攻", "tag_en": "ATTACK", "glyph": str(ak.get("name", "攻")).substr(0, 1), "name": ak.get("name", ""), "desc": ak.get("desc", ""), "col": col().lerp(Color(1, 0.9, 0.6), 0.35)})
			break
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
			fx({"kind": "mote", "pos": pos + Vector2(g.vrng.randf_range(-14, 14), g.vrng.randf_range(-40, -6)), "vel": Vector2(g.vrng.randf_range(-6, 6), -30.0 - 3.0 * power),
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
## pfx_skip > 0（docs/50 §15 D3，squad.draw_skill_over 按 render/pfx_cap 设，只在上层）：按加入先后跳过最旧的这么多个「小粒子」不画
## （PFX_CAP_KINDS：光点 / 火花 / 碎片 / 光团 / 线 / 火舌，和不循环、不走加色层的帧条）；粒子照常走完寿命，列表不动
var pfx_skip := 0
const PFX_CAP_KINDS := {"mote": true, "spark": true, "shard": true, "glow": true, "line": true, "flame": true, "strip": true}

static func pfx_cappable(f: Dictionary) -> bool:
	return PFX_CAP_KINDS.has(f.kind) and not f.get("keep", false) and not f.get("loop", false) and not f.get("add", false)


func draw_pfx(floor_layer: bool) -> void:
	var skip: int = pfx_skip if not floor_layer else 0
	for f in pfx:
		if f.get("floor", false) != floor_layer:
			continue
		if skip > 0 and pfx_cappable(f):
			skip -= 1
			continue
		# 攻击 / 技能命中的装饰扩散环（render/hit_rings，缺省不画；keep 的升级 / 召唤 / 状态提示环照画）：只跳过绘制，粒子照常走完寿命
		if f.kind == "ring" and not f.get("keep", false) and not Dc.hit_rings():
			continue
		# 后期特效密集时整体降透明度（render/world.gd 的 fx_dim，EA 1.1）；a 也传给干员自己的 _draw_pfx
		var a: float = clampf(f.life / f.max, 0.0, 1.0) * g.world.fx_dim
		if _draw_pfx(f, a):
			continue
		var c: Color = f.get("col", col())
		match f.kind:
			"ring":
				# 扩散环：r0 → r
				var k := 1.0 - a
				var rr: float = lerpf(f.get("r0", f.r * 0.3), f.r, 1.0 - (1.0 - k) * (1.0 - k))
				if f.get("floor", false):
					cv.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.55))
					cv.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 40, Color(c.r, c.g, c.b, a * f.get("alpha", 0.9)), f.get("w", 3.0))
					cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					cv.draw_arc(f.pos, rr, 0.0, TAU, 40, Color(c.r, c.g, c.b, a * f.get("alpha", 0.9)), f.get("w", 3.0))
			"spark":
				cv.draw_rect(Rect2(f.pos.round(), Vector2(f.get("sz", 3.0), f.get("sz", 3.0))), Color(c.r, c.g, c.b, a))
			"glow":
				# 发光团：先胀后缩
				var k2: float = sin(a * PI)
				cv.draw_circle(f.pos, f.r * (0.4 + 0.6 * k2), Color(c.r, c.g, c.b, f.get("alpha", 0.35) * a))
				cv.draw_circle(f.pos, f.r * 0.35 * k2, Color(c.r * 1.8, c.g * 1.8, c.b * 1.8, 0.7 * a))
			"shard":
				# 碎片：旋转的细三角
				var sv: Vector2 = Vector2.from_angle(f.get("ang", 0.0)) * f.get("sz", 6.0)
				cv.draw_colored_polygon(PackedVector2Array([f.pos - sv, f.pos + sv.orthogonal() * 0.45, f.pos + sv]), Color(c.r * 1.5, c.g * 1.5, c.b * 1.5, a))
			"line":
				cv.draw_line(f.pos, f.get("to", f.pos), Color(c.r * 1.6, c.g * 1.6, c.b * 1.6, a), f.get("w", 2.0))
			"flame":
				# 火舌：底宽上尖，随时间抖动
				var h: float = f.get("sz", 10.0) * (0.6 + 0.4 * a)
				var wob: float = sin(g.t * 24.0 + f.pos.x) * 2.0
				var bp: Vector2 = f.pos
				cv.draw_colored_polygon(PackedVector2Array([bp + Vector2(-h * 0.35, 0), bp + Vector2(wob, -h), bp + Vector2(h * 0.35, 0)]), Color(c.r, c.g, c.b, 0.8 * a))
				cv.draw_colored_polygon(PackedVector2Array([bp + Vector2(-h * 0.16, 0), bp + Vector2(wob * 0.6, -h * 0.55), bp + Vector2(h * 0.16, 0)]), Color(2.2, 1.9, 1.2, 0.8 * a))
			"mote":
				cv.draw_circle(f.pos, f.get("sz", 2.0), Color(c.r * 1.6, c.g * 1.6, c.b * 1.6, a))
			"crack":
				_draw_crack(f, a, c)


## 地裂（2026-09-26 重做，用户：原来的均匀放射线不像裂地）：第一次绘制时按落点生成并缓存在 f.crack：
## 中心是实心的不规则碎坑（深色填充 + 更深的坑心）；主裂缝 n 条（方向 / 长短随机）是实心楔形，从坑边最宽（8–12px）
## 不规则地收细到 1px，途中随机分出支裂（从主裂缝当前宽度的六成开始收细）。贴地透视（y × 0.55），中心线对齐 2 像素网格；
## 前 0.06 秒从中心裂开，暗色裂缝停留到后半程再淡出，干员色亮芯先消失。
var _gc_sink = null

func _draw_crack(f: Dictionary, a: float, c: Color) -> void:
	# 画法抽到 render/ground_crack.gd 共用（界面与美术 2026-10-01，敌人 / Boss 的地裂也用它）；缺省参数和随机数顺序不变，画面逐像素一致
	if not f.has("crack"):
		f["crack"] = GroundCrack.build(f.pos, f.r, f.get("ang"), {"n": f.get("n", 8)})
	if _gc_sink == null:
		_gc_sink = GroundCrack.CvSink.new(self)
	GroundCrack.draw(f.crack, f.max - f.life, a, c, _gc_sink)


## 子类的自定义粒子；返回 true 表示已绘制
func _draw_pfx(_f: Dictionary, _a: float) -> bool:
	return false


## 一圈火花
func fx_sparks(p: Vector2, c: Color, n: int, spd: float, life := 0.4, sz := 3.0, grav := 0.0, floor_layer := false) -> void:
	n = int(round(n * (1.0 + 0.2 * node_lv)))   # 节点越多火花越多（每节点 +20%）
	for k in n:
		fx({"kind": "spark", "pos": p, "vel": Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(spd * 0.4, spd), "life": life * g.vrng.randf_range(0.7, 1.2),
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


## 干员视角的属性值：全局修正 + 职业 / 本人作用域的修正。作用域数组与拼好的键按职业缓存（docs/101 S9；g.opt_old 的 OPT_OPS 位走旧写法）
var _sc_cls := ""
var _sc: Array = []
var _sc_key := ""

func stat(name: StringName) -> float:
	if g.opt_old & 65536:
		return g.stats.value_for(name, scopes())
	if _sc_cls != cls:
		_sc_cls = cls
		_sc = scopes()
		_sc_key = ",".join(_sc)
	return g.stats.value_for_key(name, _sc, _sc_key)


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
		parts.append("%s卡「%s」" % [g.doctor.cat_name(req.doctor_passive), g.doctor.PASSIVES.get(req.doctor_passive, {"name": req.doctor_passive}).name])
	return "、".join(parts)


## 分支培养开关（docs/119 §4.1；balance levelup/branch，缺省 1）：关着时节点按 JSON 顶层字段 = 旧成长线，同 seed TRACE 逐行不变
static func branch_on() -> bool:
	return BranchBal.vi("levelup/branch", 1) == 1


## 节点按路线解析后的视图：节点 4 带 branch {路线 id: {id, name, desc, icon, …}}、节点 5 带 routes {路线 id: {…}}，
## 已选路线时用该路线的字段覆盖顶层字段（id 决定 blocks.progression 里生效的积木与 node:<id> 条件）；
## 开关关 / 未选路线 → 原节点（顶层字段就是旧成长线：德克萨斯 回马剑 → 剑雨·再 等）
func node_view(n: Dictionary, rid: String = route) -> Dictionary:
	if n.is_empty() or not branch_on():
		return n
	var out: Dictionary = n
	if n.get("alt", null) is Dictionary:   # 开关开时无条件换成另一个节点（安洁莉娜 docs/119：双重引力提前到节点 1；顶层仍是旧线）
		out = n.duplicate()
		for k in n.alt:
			out[k] = n.alt[k]
		out.erase("alt")
	var alts = n.get("branch", n.get("routes", null))
	if alts is Dictionary and rid != "" and alts.has(rid) and alts[rid] is Dictionary:
		if out == n:
			out = n.duplicate()
		for k in alts[rid]:
			out[k] = alts[rid][k]
		out.erase("branch")
		out.erase("routes")
	return out


## 整条成长线按当前路线解析（属性面板 / 图鉴）
func prog_view() -> Array:
	var out: Array = []
	for n in progression():
		out.append(node_view(n))
	return out


## 节点 n 是不是分支节点（开关开、带非空 branch）
func is_branch_node(n: Dictionary) -> bool:
	return branch_on() and n.get("branch", null) is Dictionary and not (n.branch as Dictionary).is_empty()


## 下一个节点要不要先选路线（分支节点且还没选）
func needs_route() -> bool:
	return route == "" and is_branch_node(next_node())


## 路线选项 {路线 id: {id, name, desc, icon, col?}}（分支节点；非分支节点为空）
func route_choices(n: Dictionary = next_node()) -> Dictionary:
	if not is_branch_node(n):
		return {}
	var out: Dictionary = {}
	for k in n.branch:
		if n.branch[k] is Dictionary:
			out[k] = n.branch[k]
	return out


## 机器人 / 赠送推进（典训、博士银印）/ 测试直接 advance("") 时的固定路线（docs/119 §4.1：可记录、不凭界面外随机）：
## --route=<op>:<路线>（可逗号分几人，调试构建）→ 节点 "bot" 字段 → 第一条路线
func bot_route(n: Dictionary) -> String:
	var chs := route_choices(n)
	if chs.is_empty():
		return ""
	for a in (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()):
		if a.begins_with("--route="):
			for part in a.substr(8).split(","):
				var kv: PackedStringArray = part.split(":")
				if kv.size() == 2 and kv[0] == id and chs.has(kv[1]):
					return kv[1]
	var b: String = str(n.get("bot", ""))
	return b if chs.has(b) else str(chs.keys()[0])


## 应用下一个成长节点（elite 节点可带 choice；分支节点 choice = 路线 id）。
## 分支节点没给路线、也没选过时：玩家局交给 progression.branch_defer 进路线选择画面（本次不推进，确认后再调一次），
## 机器人 / 测试 / 演示按 bot_route 固定选。节点 4 / 5 的 id、文字按 node_view 解析后再应用，所以同一节点不会重复加成
func advance(choice: String = "") -> void:
	var n := next_node()
	if n.is_empty():
		return
	if is_branch_node(n):
		var rid: String = choice if n.branch.has(choice) else route
		if rid == "" or not n.branch.has(rid):
			if g.get("progression") != null and g.progression.branch_defer(self):
				return
			rid = bot_route(n)
		route = rid
		choice = ""
	n = node_view(n)
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
			fx({"kind": "ring", "pos": pos, "r": 46.0, "r0": 6.0, "life": 0.45, "col": col(), "floor": true, "w": 3.0, "keep": true})
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
		if needs_route():
			# 分支节点（docs/119 §4.1）：外层只出一张培养卡，选中后进二选一（progression.open_branch）；卡面列出两条路线
			var rc := route_choices(n)
			var names: Array = []
			for k in rc:
				names.append("「%s」" % str(rc[k].get("name", k)))
			var bdesc: String = str(n.get("branch_desc", "选定一条培养路线：%s。之后的节点沿同一路线强化。" % " / ".join(names)))
			out.append({"kind": "prog", "op": id, "choice": "", "branch": true, "name": "%s · %s" % [display_name(), n.get("name", "培养路线")],
				"desc": bdesc + ("；攻击 +%d%%" % int(round(NODE_ATK * 100.0))) + (("\n条件：%s（已满足）" % node_requires_text(n)) if node_requires_text(n) != "" and avail else ""),
				"icon": n.get("icon", ""), "avail": avail, "req": node_requires_text(n), "elite": 0})
		elif not chs.is_empty():
			for c in chs:
				var cd: Dictionary = chs[c]
				out.append({"kind": "prog", "op": id, "choice": c, "name": "%s · %s" % [n.get("name", "精英化"), cd.get("name", c)],
					"desc": cd.get("desc", n.get("desc", "")), "icon": cd.get("icon", n.get("icon", "")), "col": cd.get("col", null), "avail": avail, "req": node_requires_text(n), "elite": n.level})
		else:
			n = node_view(n)   # 节点 5：按已选路线的名字 / 说明 / 图标
			var req_txt := node_requires_text(n)
			# 普通节点另带统一的攻击 +6%（NODE_ATK，advance()）：写在卡面说明末尾，免得这部分成长看不见
			var node_atk: String = ("；攻击 +%d%%" % int(round(NODE_ATK * 100.0))) if n.get("type", "") != "elite" else ""
			out.append({"kind": "prog", "op": id, "choice": "", "name": "%s · %s" % [display_name(), n.get("name", "成长 " + stage_txt)],
				"desc": n.get("desc", "") + node_atk + (("\n条件：%s（已满足）" % req_txt) if req_txt != "" and avail else ""), "icon": n.get("icon", ""), "avail": avail, "req": req_txt, "elite": n.get("level", 0)})
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
	var n: int = anim_hframes(tx, "idle") if tx != null else 1
	var tn: String = spec.get("tex", "")
	if tx != null and sprite_mirror("idle"):
		# 待机条画反了（docs/84）：头像用镜像副本，登记进 g.tex（HUD 按名字取图）
		var mn: String = tn + "~mirror"
		if not g.tex.has(mn):
			g.tex[mn] = A.mirror_strip(tx, n)
		tn = mn
	return {"tex": tn, "frames": n}


# ---------------------------------------------------------------- 跟随与动画（squad.gd 调用）

## 队友跟随停顿（10-21，用户定方案 C 为缺省；--fpause=off|a|b 对照，off = 原来每帧 lerp 追槽位）：
##   a 到位滞回：进槽位 FP_ARRIVE 像素内站定，至少停 FP_HOLD 秒，偏离超过 FP_LEAVE 才再起步；
##   b 错开起步：站定后要起步时按编队位延迟 FP_DELAY0 + slot × FP_DELAY_STEP 秒（约 0.08–0.15）；
##   c 两者都开。纯跟随位移，有意改变同 seed（队友位置影响出手范围 / 索敌）
const FP_ARRIVE := 14.0
const FP_LEAVE := 32.0
const FP_HOLD := 0.3
const FP_DELAY0 := 0.045
const FP_DELAY_STEP := 0.035
static var follow_pause := -1   # -1 未读；缺省 3 = c（10-21 用户定）；--fpause=off|a|b|c 作对照
var fp_moving := true
var fp_t := 0.0
var fp_wait := -1.0

func _follow_paused(dt: float, d: float) -> bool:
	if follow_pause < 0:
		follow_pause = 3
		for a in (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()):   # 发布版不读命令行（check_release）；不用 Cfg：核心契约测试无 autoload，同第 265 行写法
			if a.begins_with("--fpause="):
				follow_pause = maxi(0, "-abc".find(a.substr(9, 1)))   # off → 0
	if follow_pause == 0:
		return false
	var hold: bool = follow_pause != 2
	var stagger: bool = follow_pause != 1
	if fp_moving:
		if d < FP_ARRIVE:
			fp_moving = false
			fp_t = FP_HOLD if hold else 0.0
		return false
	fp_t -= dt
	if d <= (FP_LEAVE if hold else FP_ARRIVE + 2.0) or fp_t > 0.0:
		fp_wait = -1.0
		return true
	if stagger:
		if fp_wait < 0.0:
			fp_wait = FP_DELAY0 + float(slot) * FP_DELAY_STEP
		fp_wait -= dt
		if fp_wait > 0.0:
			return true
	fp_wait = -1.0
	fp_moving = true
	return false


## 跟随主控的编队位：近处慢慢挪、远处快步跟上；离得太远（开局 / 传送）直接归位
func follow(dt: float, target: Vector2) -> void:
	var sq = g.get("squad")
	var st: int = sq.stance if sq != null and not is_leader else 0   # 指挥模式（docs/114）：0 随行 / 1 突击 / 2 归队
	if st == 1 and not cmd_roam():
		st = 0   # 不突击的干员（json command.roam: false）突击时照旧随行
	if pos == Vector2.INF or pos.distance_to(target) > (700.0 if st == 0 else CmdBal.v("command/leash", 960.0) * 1.6):
		pos = target
		mv = 0.0
		return
	var prev: Vector2 = pos
	if is_leader:
		pos = target   # 主控：位置就是玩家位置（g.ppos），不走编队跟随 / 近战前压
	else:
		target = roam_target(target) if st == 1 else follow_target(target)
		if st == 2 and sq.gather_t >= 0.0:
			target = pos   # 归队集合：到位后站定一下（squad._tick_recall）
		if cmd_down > 0.0 and st == 1:
			target = pos   # 突击中倒地：原地躺着（squad._tick_hp）；归队后随队回位，躺着跟着编队位继续复活计时
		var d: float = pos.distance_to(target)
		var k: float = clampf(dt * (3.0 if d < 20.0 else (9.0 if st == 2 else 6.0)), 0.0, 1.0)
		cmd_d = d
		if st == 0:
			if not _follow_paused(dt, d):   # 随行：到位停 + 错开起步（10-21 用户定方案 C）
				pos = pos.lerp(target, k)
		else:
			fp_moving = true   # 突击 / 归队不停顿；回到随行时从「在走」开始
			# 突击 / 归队：限速（随行原样不限）——突击按队长移速 × command/roam_speed 跑过去，归队 × command/recall_speed 快速归位
			var step: Vector2 = (target - pos) * k
			var vmax: float = g.speed * CmdBal.v("command/roam_speed" if st == 1 else "command/recall_speed", 1.3 if st == 1 else 4.0) * dt
			if step.length() > vmax:
				step = step.normalized() * vmax
			pos += step
		if g.tex.get("prop_pillar") != null:
			pos = g.map.push_out(pos, 10.0)
	var vel: Vector2 = (pos - prev) / maxf(dt, 0.0001)
	_sample_motion(vel, dt)
	var sp_now: float = vel.length()
	mv = lerpf(mv, sp_now, clampf(dt * (10.0 if sp_now > mv else 20.0), 0.0, 1.0))   # 停下衰减快一倍，不再停住后多跑 0.15–0.27 秒
	if attack_t <= 0.0:
		if absf(vel.x) > 25.0 and mv > 30.0:
			# 主控跟着玩家移动即时转身；队友明显横向移动（> 90）时也即时转，不再倒着跑
			# 主控即时；队友明显横向移动（> 90）且距上次翻身满 0.15 秒也转（倒着跑），否则走 FACE_MIN 防抖（runretest2）
			_set_face(signf(vel.x), is_leader or (absf(vel.x) > 90.0 and g.t - face_flip_t >= 0.15))
		elif mv < 20.0 and g.t - face_flip_t > FACE_IDLE:
			_set_face(g.facing)   # 站定回正：离上次翻身满 FACE_IDLE 秒才回，免得出手转向后立刻翻回来
	attack_t = maxf(0.0, attack_t - dt)
	if fire_t >= 0.0:
		fire_t -= dt
		if fire_t < 0.0:
			fire_t = -1.0
			if act_kind == "skill":
				_release_skill()
			else:
				_release()
				_notify_attack()
	mt += dt
	_tick_sq(dt)
	# 动画状态
	var want := "idle"
	var sqk := _sq_kind()   # 多条技能帧条当前阶段的帧条（"" = 不在序列里）
	if vis_anim != "" and anim_tex(vis_anim) != null:
		want = vis_anim   # 纯画面动作（play_vis_anim）：播完前压过普攻 / 跑步，不占出手窗口
	elif sq_atk != "" and anim_tex(sq_atk) != null:
		want = sq_atk   # 循环期间的普攻变体（sprites.skills.sN.attack）：按其 fire 帧对齐出手，播完回循环（_tick_sq_atk）
	elif attack_t > 0.0 and not sq_own and anim_tex(act_anim) != null:
		want = act_anim   # 序列之外的动作（循环期间起手的普攻 / 另一技能）压过序列，播完接着循环
	elif sqk != "":
		want = sqk   # 序列自己的起手 / 定格 / 循环 / 收势（起手段同时也是出手窗口；序列结束后 sq_own 的窗口余下部分回待机）
	elif mv > (RUN_EXIT if anim_kind == "run" else RUN_ENTER) and anim_tex("run") != null:
		want = "run"   # 跑 / 停加滞回：起跑 RUN_ENTER、停下 RUN_EXIT，不在两者间来回闪
	if want != anim_kind:
		if want == "run" and anim_kind == "idle":
			run_ph = 0.0   # 只有从站立起跑才从第 0 帧开始；出手结束接着原来的跑步相位（原来每次从头，6 帧循环播不完）
		anim_kind = want
		anim_t = 0.0
	anim_t += dt
	if vis_anim != "" and anim_kind == vis_anim and anim_t >= vis_dur():
		vis_anim = ""   # 播完回待机（末帧 = 待机 f0，收招不跳）
	_tick_sq_shadow(dt)
	# 跑步帧率按实际移动速度缩放（原固定 fps：快速前压的近战队友脚步打滑 3 倍以上）；帧条按主控基础移速 RUN_REF 画
	if anim_kind == "run":
		run_ph += dt * float(sprite_spec("run").get("fps", ANIM_FPS.get("run", 10.0))) * clampf(mv / RUN_REF, RUN_K_MIN, RUN_K_MAX)


## 起手：面向目标、播攻击条（4 帧 8fps 约定：0.5 秒，零基第 2 帧出手）；没有攻击条就立即出手
## 贴图槽带 fps + fire（出手帧，零基）时，时长与出手时刻按帧条算，dur / fire_at 参数被忽略（docs/24 §1）
## anim：这一击改播别的帧条（例如斯卡蒂潮汐期间播 "attack_spin"）；缺图时退回 attack 条。出手仍调 _release（逻辑类型不变）
static func valid_attack_timing(spec: Dictionary) -> bool:
	return OperatorContract.valid_attack_timing(spec)


static func valid_frame_durations(spec: Dictionary) -> bool:
	return OperatorContract.valid_frame_durations(spec)


## 逻辑窗口（docs/108 §4 sprites.<槽>.logic = [旧帧数, 旧 fps, 旧出手帧]）：换新帧条后按旧条的同一算式求总时长与出手时刻，
## 与旧 frames / fps、(fire + 0.5) / fps 逐位相同。frame_durations / fire_time 这时只管画面——Godot 解析 json 长小数不逐位精确
## （0.20833333333333334 读成 …37），用它们定逻辑会让同 seed 偶尔差一帧。
static func logic_window(spec: Dictionary) -> Array:
	var lg: Array = spec.logic
	return [float(lg[0]) / float(lg[1]), (float(lg[2]) + 0.5) / float(lg[1])]   # 不用 Vector2（单精度）


func frame_seconds(kind: String, frame: int) -> float:
	var spec := sprite_spec(kind)
	return float(spec.frame_durations[frame]) if spec.has("frame_durations") else 1.0 / float(spec.get("fps", 12.0))


func frames_seconds(kind: String, frames: Array) -> float:
	var total := 0.0
	for frame in frames:
		total += frame_seconds(kind, int(frame))
	var spec := sprite_spec(kind)
	if spec.has("frame_durations") and spec.has("fps") and frames.size() == int(spec.get("frames", 0)):
		var nominal := frames.size() / float(spec.fps)
		# 完整帧条的求和舍入不能改变原有动作占用的物理帧数。
		if absf(total - nominal) < 0.000000000001:
			return nominal
	return total


## 倒地画面（10-22）：本人 death 条按 frame_durations / fps 播一遍、停在末帧；没有 death 条返回 {}（调用方照旧画当前帧）。
## 队长倒下（draw_body）、队友离队 / 换人（squad._leave_fx 的 g.fx kind "downed"）、突击倒地共用
func downed_state(age: float) -> Dictionary:
	var tx: Texture2D = anim_tex("death")
	if tx == null:
		return {}
	var n: int = anim_hframes(tx, "death")
	var spec := sprite_spec("death")
	var fr: int
	if spec.has("frame_durations"):
		fr = timed_frame("death", range(n), age)
	else:
		fr = mini(int(age * float(spec.get("fps", ANIM_FPS.death))), n - 1)
	return {"tex": tx, "frame": fr, "hf": n, "flip": (face < 0.0) != sprite_mirror("death"), "kind": "death"}


## 倒地播完的秒数（离队 fx 的寿命用）
func downed_seconds() -> float:
	var tx: Texture2D = anim_tex("death")
	if tx == null:
		return 0.0
	var n: int = anim_hframes(tx, "death")
	if sprite_spec("death").has("frame_durations"):
		return frames_seconds("death", range(n))
	return n / float(sprite_spec("death").get("fps", ANIM_FPS.death))


func timed_frame(kind: String, frames: Array, elapsed: float, looping := false) -> int:
	if frames.is_empty():
		return 0
	var age := fposmod(elapsed, frames_seconds(kind, frames)) if looping else elapsed
	for frame in frames:
		age -= frame_seconds(kind, int(frame))
		if age < 0.0:
			return int(frame)
	return int(frames[-1])


func start_attack(aim: Vector2, dur: float = 0.5, fire_at: float = 0.25, anim := "", interval := 0.0) -> void:
	_start_action("attack", aim, dur, fire_at, anim, interval)


## 起手技能动作；idx 为技能序号（默认沿用 cur_skill）。播哪套帧条由 skill_anim() 决定（缺省 skill 条），
## anim 参数可临时指定；那套帧条不存在时退回 skill 条，都没有就直接出手
func start_skill(aim: Vector2, idx: int = -1, dur: float = 0.6, fire_at: float = 0.3, anim := "") -> void:
	if idx >= 0:
		cur_skill = idx
		spend_sp(idx)
	if anim == "" and _start_skill_seq(aim, cur_skill):
		return   # 多条技能帧条（sprites.skills，见下）
	_start_action("skill", aim, dur, fire_at, anim if anim != "" else skill_anim(cur_skill))


## 技能 i 播放的帧条（2026-09-26）：缺省读干员 JSON skills[i].anim（例如 "attack" = 放技能时播普攻动作），没写就是 "skill"。
## 干员脚本也可以重写这个函数按状态决定。出手时机按实际播放的那套帧条的 fps / fire 算。
func skill_anim(i: int) -> String:
	if i < 0:
		return "skill"
	return str(skill_def(i).get("anim", skill_seq(i).get("anim", "skill")))   # sprites.skills.sN 只写 anim 的单条同 skills[i].anim（docs/87 §3.5）


## 独立视觉叠层，不调度伤害；保留给既有展示和视觉技能调用。
var vis_anim := ""

func play_vis_anim(kind: String) -> void:
	if anim_tex(kind) == null:
		return
	vis_anim = kind
	anim_kind = kind
	anim_t = 0.0


## 充满即发干员的技能画面（10-16 水月 S2）：写了 sprites.skills.sN 序列（start / loop / end 或 intro / hold）就按序列播（纯画面：
## 不占出手窗口，attack_t / fire_t / 朝向都不动，同 seed 模拟不变；loop 跟着 skill_active_left(i) 走，结束播 end），否则单条 play_vis_anim
func play_vis_skill(i: int) -> void:
	if _start_vis_seq(i):
		return
	play_vis_anim(skill_anim(i))


## 纯画面动作的时长：帧数 / fps（没写 fps 按 12）
func vis_dur() -> float:
	var spec := sprite_spec(vis_anim)
	var n := float(spec.get("frames", anim_hframes(anim_tex(vis_anim), vis_anim)))
	return frames_seconds(vis_anim, range(int(n)))


## kind：逻辑类型（attack / skill，决定出手调哪个函数）；anim：播放的帧条（缺省同 kind）
func _start_action(kind: String, aim: Vector2, dur: float, fire_at: float, anim := "", interval := 0.0) -> void:
	if aim != Vector2.INF and absf(aim.x - pos.x) > FACE_DEAD:
		_set_face(signf(aim.x - pos.x))
	if not (seq_locked() and kind == "attack"):
		_sq_interrupt()
	act_kind = kind
	act_anim = anim if anim != "" and (anim_tex(anim) != null or sprite_spec(anim).has("frames")) else kind
	if anim_tex(act_anim) == null and not sprite_spec(act_anim).has("frames"):
		if kind == "skill":
			_release_skill()
		else:
			_release()
			_notify_attack()
		return
	var spec := sprite_spec(act_anim)
	if spec.has("fps") and spec.has("fire"):
		var n := float(spec.get("frames", anim_hframes(anim_tex(act_anim), act_anim)))
		dur = n / float(spec.fps)
		fire_at = (float(spec.fire) + 0.5) / float(spec.fps)
	if spec.has("frame_durations"):
		dur = frames_seconds(act_anim, range(int(spec.frames)))
		fire_at = float(spec.get("fire_time", fire_at))
	if spec.has("logic"):
		var lw := logic_window(spec)
		dur = lw[0]
		fire_at = lw[1]
	attack_phased = kind == "attack" and spec.has("attack_timing")
	if attack_phased:
		var timing: Dictionary = spec.attack_timing
		dur = float(timing.duration)
		if interval > 0.0:
			dur = maxf(float(timing.get("min_duration", 0.0)), minf(dur, interval * float(timing.active_ratio)))
		fire_at = minf(float(timing.fire_time), dur * float(timing.windup_ratio))
	attack_fire_at = fire_at
	attack_dur = dur
	attack_t = dur
	fire_t = fire_at
	anim_kind = act_anim   # 直接切到出手帧条（原来置空，同帧 anim_state 退回待机，每次起手闪一帧）
	anim_t = 0.0
	# 持续技能攻击变体在起手当帧就接管，避免露出一帧普通攻击。
	_tick_sq_atk(0.0)
	if sq_atk != "":
		anim_kind = sq_atk


## 出手（到出手帧时调用；重新找目标，动作期间原目标可能已死）
func _release() -> void:
	pass


## 普攻出手后告诉编队里的其他干员（数据干员的 trig.on_mate_attack：能天使「天使的祝福」给受祝福的队友出手点挂金光；只有画面）
func _notify_attack() -> void:
	var sq = g.get("squad") if g != null else null
	if sq == null:
		return
	for m in sq.ops:
		if m != self and m.has_method("on_mate_attack"):
			m.on_mate_attack(self)


## 技能出手帧（cur_skill 为技能序号）
func _release_skill() -> void:
	pass


## 是否正在播放动作（攻击 / 技能），用于避免打断
func acting() -> bool:
	return attack_t > 0.0


## 跟随目标点：默认是编队位；近战干员可以改成"前压到敌人身边"（离主控不超过 leash）
func follow_target(slot_pos: Vector2) -> Vector2:
	return slot_pos


## 指挥模式（docs/114）：这名干员突击时是否离队找怪（json command.roam，缺省 true；医疗 / 辅助写 false）
func cmd_roam() -> bool:
	return bool(def.get("command", {}).get("roam", true))


## 突击时离敌人多远站定（近战贴身、远程退到射程内），子类按普攻定义覆盖
func cmd_reach() -> float:
	return 30.0


## 突击站位：自己身边 command/search 内最近的敌人（离队长不超过 command/leash），站到它朝自己一侧 cmd_reach 处；
## 现目标死亡 / 出圈才换，身边出现明显更近的（近 GUARD_MARGIN 以上）也换。没怪 = 回编队位。只读 op_api 索敌，不抽随机数
const CmdBal = preload("res://scripts/core/balance.gd")
var roam_tgt = null
var cmd_d := 0.0   # 本帧到跟随目标的距离（归队是否归位完由 squad 读）

## 突击站位按职业（10-22 原型，docs/114 §7）：重装 wall 站到怪群与队长之间；狙击 / 术师 kite 保持射程绕圈；其余 melee 贴怪群边缘
func cmd_role() -> String:
	if cls == "重装":
		return "wall"
	if cls in ["狙击", "术师"]:
		return "kite"
	return "melee"


## 突击生命（squad._tick_hp）：cmd_hp 0–1；cmd_down > 0 = 倒地剩余秒数；cmd_inv 无敌剩余；cmd_show 血条显示剩余
var cmd_hp := 1.0
var cmd_down := 0.0
var cmd_down_age := 0.0
var cmd_inv := 0.0
var cmd_show := 0.0

## 断后站位（10-22 用户：别跑太远、要有留下来断后的感觉）：活动圈 = 队长周围 command/roam_r（约 0.5–0.7 屏，屏内）；
## 只在圈内挑怪，优先队长身后（移动方向反侧 command/rear_d 处，队长不动时取圈内怪群中心）最近的；队长往前走时不跟着冲，
## 守着目标直到它出圈（滞回 ×1.15）或被圈边拉回，看起来就是「拖住一段再追上」。重装站在队长与身后怪群之间；近战贴在怪朝队长那一侧；
## 远程在目标外沿 reach 处绕圈（仍在圈内，即队长侧后方）
func roam_target(slot_pos: Vector2) -> Vector2:
	var R: float = CmdBal.v("command/roam_r", 380.0)
	var role := cmd_role()
	var sq = g.squad
	var ld: Vector2 = sq.lead_dir if sq != null else Vector2.ZERO
	var rear: Vector2 = g.ppos - ld * CmdBal.v("command/rear_d", 160.0) if ld != Vector2.ZERO else g.ppos
	if role == "wall":
		var ns: Array = nearest_enemies(6, R, rear).filter(func(en): return en.pos.distance_to(g.ppos) <= R)
		if ns.is_empty():
			return slot_pos
		var c := Vector2.ZERO
		for en in ns:
			c += en.pos
		c /= float(ns.size())
		var tw: Vector2 = c - g.ppos
		if tw.length() < 1.0:
			return slot_pos
		return g.ppos + tw.normalized() * clampf(tw.length() * 0.6, 50.0, R * 0.7)
	var e = roam_tgt
	if e == null or e.dead or e.pos.distance_to(g.ppos) > R * 1.15:
		e = null
		for en in nearest_enemies(4, R, rear):
			if en.pos.distance_to(g.ppos) <= R:
				e = en
				break
	roam_tgt = e
	if e == null:
		return slot_pos
	var reach: float = cmd_reach() + e.r
	var p: Vector2 = pos
	if role == "kite":
		# 远程放风筝：站在离目标 reach 的圆上，沿圆周往前挪（编队位单双号决定顺 / 逆时针），被贴近就后退
		var dv: Vector2 = pos - e.pos
		if dv.length() < 1.0:
			dv = Vector2(-face, 0)
		p = e.pos + dv.normalized().rotated(CmdBal.v("command/kite_step", 0.5) * (1.0 if slot % 2 == 0 else -1.0)) * reach
	else:
		# 近战：贴在怪朝队长的那一侧（挡在队长和追兵之间）；已经够得着就原地打
		if pos.distance_to(e.pos) > reach + 14.0:
			var tl: Vector2 = g.ppos - e.pos
			if tl.length() < 1.0:
				tl = Vector2(-face, 0)
			p = e.pos + tl.normalized() * reach
	var off: Vector2 = p - g.ppos
	if off.length() > R:
		p = g.ppos + off.normalized() * R   # 超出活动圈往回收
	return p


## 近战前压：主控 leash 范围内最近的敌人；返回站位点（敌人朝主控一侧、身前 gap 处）或 INF。
## 目标带滞回（现目标死亡或超出 leash × 1.3 才换），已经够得着时原地不动，避免在两个目标 / 两侧之间来回抖。
var melee_tgt = null

const GUARD_MARGIN := 50.0

func melee_spot(leash: float, gap: float) -> Vector2:
	if g.demo_op != "":
		leash *= 2.0   # 图鉴演示：场地里全是靶子，近战放宽前压范围，一直追着怪海打
	var e = melee_tgt
	var near: Array = nearest_enemies(1, leash, g.ppos)
	var n0 = near[0] if not near.is_empty() else null
	if e == null or e.dead or e.pos.distance_to(g.ppos) > leash * 1.3:
		e = n0
		melee_tgt = e
	elif n0 != null and not is_same(n0, e) and n0.pos.distance_to(g.ppos) + GUARD_MARGIN < e.pos.distance_to(g.ppos):
		# 护主（2026-09-27 range-melee r2）：主控身边出现明显更近的怪就换过去，不再死追远处的目标
		e = n0
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


## 近战扇形命中：对 origin 周围 radius、朝 ang ±half 的敌人造成伤害；返回命中的敌人。
## max_n > 0：最多打 max_n 个（cap_targets 的顺序：Boss → 精英 → 其余，同档按离 origin 由近到远、再按 id；docs/61 §3.3 max_n）
func melee_hit(src: String, origin: Vector2, ang: float, half: float, radius: float, dmg: float, kb := 0.0, stun := 0.0, tags: Array = [], max_n := 0) -> Array:
	var hits: Array = arc_targets(origin, ang, half, radius)
	if max_n > 0 and hits.size() > max_n:
		hits = cap_targets(hits, origin, max_n)
	var ve: float = vs_elite()
	for e in hits:
		log_hit(src, tags)
		deal_damage(e, dmg * (ve if e.elite or e.boss else 1.0))
		if e.dead or e.boss:
			continue
		if kb > 0.0:
			apply_kb(e, (e.pos - origin).normalized() * kb * (0.3 if e.elite else 1.0))   # 失重（st.weightless，安洁莉娜天赋）：受到的击退更远；没失重乘 1.0
		if stun > 0.0:
			add_cc(e, stun * (0.5 if e.elite else 1.0))
	for e in hits:
		_hit_fx(e, origin)
	return hits


## 对精英 / Boss 的伤害倍率（JSON base.vs_elite，缺省 1）：melee_hit / area_hit 自动乘；自己推进弹体的干员在生成时乘。
## 2026-09-27 数值 b1-cal：铃兰 / 塞雷娅开局主控时中期 Boss 太慢，给这两人加
func vs_elite() -> float:
	return base("vs_elite", 1.0)


## 命中一名敌人时的特效钩子（默认无；各干员按 docs/25 覆盖）
func _hit_fx(_e: Dictionary, _origin: Vector2) -> void:
	pass


## 圆形范围伤害（技能 / 爆炸）：返回命中的敌人；max_n 同 melee_hit
func area_hit(src: String, c: Vector2, radius: float, dmg: float, kb := 0.0, stun := 0.0, tags: Array = [], max_n := 0) -> Array:
	return melee_hit(src, c, 0.0, PI, radius, dmg, kb, stun, tags, max_n)


## 从命中列表里挑 n 个（确定性，不用随机数）：Boss → 精英 → 其余，同档离 origin 近的先，再按 id
static func cap_targets(hits: Array, origin: Vector2, n: int) -> Array:
	var keyed: Array = []
	for e in hits:
		keyed.append([0 if e.boss else (1 if e.elite else 2), origin.distance_squared_to(e.pos), int(e.id), e])
	keyed.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else (a[1] < b[1] if a[1] != b[1] else a[2] < b[2]))
	var out: Array = []
	for k in mini(n, keyed.size()):
		out.append(keyed[k][3])
	return out


## 技能强度倍率（全队被动「协同·锐」等）
func skill_power() -> float:
	return stat(&"op_skill_power")


## 干员面向某个方向（出手时由干员调用）。目标几乎在正上 / 正下方（水平分量 < 25%）时不转，免得来回翻
func face_to(ang: float) -> void:
	var c := cos(ang)
	if absf(c) < 0.25:
		return
	_set_face(1.0 if c > 0.0 else -1.0)


## 朝向防抽搐（2026-09-26 用户反馈「左右抽搐」）：出手转向要求目标越过身体中线 FACE_DEAD 以上（_start_action），
## 且距上次翻身至少 FACE_MIN 秒；两侧都有敌人时不再每一击都翻身。force = 主控跟随玩家移动的转身，即时生效
const FACE_DEAD := 14.0
const FACE_MIN := 0.35
const FACE_IDLE := 1.0
var face_flip_t := -99.0

func _set_face(want: float, force := false) -> void:
	if want == 0.0 or want == face:
		return
	if not force and g != null and g.t - face_flip_t < FACE_MIN:
		return
	face = want
	face_flip_t = g.t if g != null else 0.0


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


## 帧条朝向标记（2026-10-13，docs/84）：sprites.<kind>.mirror = true 表示这条帧条画成了朝左（约定一律朝右），
## 绘制时把它当作已翻转处理：战斗里翻转标志取反（脚底锚点 foot 按源图量，foot_dx 随翻转自动换算成 宽 − x），
## 界面贴图用 A.mirror_strip 的镜像副本。美术返修交付后删掉标记即可
static func strip_mirror(d: Dictionary, kind: String) -> bool:
	var v = d.get("sprites", {}).get(kind, null)
	return v is Dictionary and bool(v.get("mirror", false))


func sprite_mirror(kind: String) -> bool:
	return strip_mirror(def, kind)


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


## 当前帧（贴图 / 帧序号 / 帧数），残影 / 分身等复用。道具离手（prop_out）时换成无盾画面（_noshield）
func anim_state() -> Dictionary:
	return _noshield(_anim_state_raw())


func _anim_state_raw() -> Dictionary:
	if seq_locked():   # sprites.skills.sN.lock：序列持续 / 收势期间只播序列（艾丽妮 S3 只播空中连射，普攻照常结算不换画面）
		var lk := _sq_kind()
		var ltx: Texture2D = anim_tex(lk) if lk != "" else null
		if ltx != null:
			var ln: int = anim_hframes(ltx, lk)
			return {"tex": ltx, "frame": _sq_frame(ln), "hf": ln, "flip": (face < 0.0) != sprite_mirror(lk), "kind": lk}
	var tx: Texture2D = anim_tex(anim_kind)
	if tx == null:
		tx = anim_tex("idle")
	if tx == null:
		return {}
	var kind: String = anim_kind if anim_tex(anim_kind) != null else "idle"
	var n: int = anim_hframes(tx, kind)
	var fr := 0
	if sq_atk != "" and kind == sq_atk:
		return {"tex": tx, "frame": _sq_atk_frame(n), "hf": n, "flip": (face < 0.0) != sprite_mirror(kind), "kind": kind}
	if sq_ph != 0 and kind == _sq_kind():
		return {"tex": tx, "frame": _sq_frame(n), "hf": n, "flip": (face < 0.0) != sprite_mirror(kind), "kind": kind}
	if vis_anim != "" and kind == vis_anim:
		fr = timed_frame(kind, range(n), anim_t)   # 纯画面动作播一遍，停在末帧
		return {"tex": tx, "frame": fr, "hf": n, "flip": (face < 0.0) != sprite_mirror(kind), "kind": kind}
	if sprite_spec(kind).has("frame_durations") and act_anim == kind and attack_t > 0.0:
		fr = timed_frame(kind, range(n), attack_dur - attack_t)
		return {"tex": tx, "frame": fr, "hf": n, "flip": (face < 0.0) != sprite_mirror(kind), "kind": kind}
	match kind:
		"attack", "skill":
			fr = attack_phase_frame(n, int(sprite_spec(kind).get("fire", 0)), attack_dur - attack_t) if attack_phased and act_kind == "attack" else clampi(int(anim_t / attack_dur * n), 0, n - 1)
		"run":
			fr = int(run_ph) % n
		_:
			fr = timed_frame(kind, range(n), anim_t, true) if sprite_spec(kind).has("frame_durations") else int(anim_t * float(sprite_spec(kind).get("fps", ANIM_FPS.get(kind, 4.0)))) % n
	return {"tex": tx, "frame": fr, "hf": n, "flip": (face < 0.0) != sprite_mirror(kind), "kind": kind}


## 每击完整经过前摇、出手、收势；伤害事件位于出手帧起点。
func attack_phase_frame(n: int, release_frame: int, elapsed: float) -> int:
	if elapsed < attack_fire_at:
		return clampi(int(elapsed / maxf(attack_fire_at, 0.000001) * release_frame), 0, release_frame - 1)
	return clampi(release_frame + int((elapsed - attack_fire_at) / maxf(attack_dur - attack_fire_at, 0.000001) * (n - release_frame)), release_frame, n - 1)


## ---- 帧条里的定位点（10-15，星熊「盾心」）：def.sprites.<动作>.<key> = 每帧一个 [x, y]（1x 美术像素，帧内坐标，同 foot 的口径；
## null = 这一帧没有，比如盾已离手）。返回当前帧这个点的世界坐标（朝左镜像、@2x 按倍率折算都由 foot 口径自然消掉；含屏幕抖动 draw_off，
## 与本体画在同一处）；这一帧 / 这个动作没有标、或道具离手（prop_out）时返回 Vector2.INF
func sprite_point(key: String) -> Vector2:
	if pos == Vector2.INF or (key == "shield" and prop_out()):
		return Vector2.INF
	var st := anim_state()
	if st.is_empty():
		return Vector2.INF
	return sprite_point_at(str(st.get("kind", "")), key, int(st.get("frame", 0)), -1, st.get("flip", false))


## 指定帧条 / 帧 / 点名的世界坐标（docs/108 §4，所有逐帧定位点与炮口共用这一份换算）：
## idx ≥ 0 时该帧的点是一组（如 muzzles[帧][发]）取第 idx 个；flip 缺省 = 当前朝向异或帧条 mirror。
## 含 pt_foot（缺省 = 槽 foot / 顶层 foot）与 sprites.draw_scale；screen = true 时再加屏幕抖动 draw_off（与本体画在同一处）。
## 玩法用的点（炮口 = 弹体起点）传 screen = false：draw_off 是绘制期的状态，玩法读它会让无头与有窗口的结果分叉
func sprite_point_at(kind: String, key: String, frame: int, idx := -1, flip = null, screen := true) -> Vector2:
	if pos == Vector2.INF:
		return Vector2.INF
	var spec := sprite_spec(kind)
	var pts = spec.get(key, null)
	if not (pts is Array) or pts.is_empty():
		return Vector2.INF
	var p = pts[frame % pts.size()]
	if idx >= 0:
		p = p[idx] if p is Array and idx < p.size() else null
	if not (p is Array) or p.size() < 2:
		return Vector2.INF
	var ft = spec.get("foot", def.get("sprites", {}).get("foot", [24, 46]))
	# pt_foot：这些点量的时候用的脚底（换画布时只改 foot、不重标点：48 → 64 画布把旧 foot 写进 pt_foot 即可，docs/103 §5）；缺省 = foot
	var pf = spec.get("pt_foot", ft)
	var fl: bool = ((face < 0.0) != sprite_mirror(kind)) if flip == null else bool(flip)
	var sgn: float = -1.0 if fl else 1.0
	var ds: float = float(def.get("sprites", {}).get("draw_scale", 1.0))
	return pos + (g.draw_off if screen else Vector2.ZERO) + Vector2(sgn * (float(p[0]) - float(pf[0])), float(p[1]) - float(pf[1])) * g.PX * ds


## 道具离手（星熊「般若回旋」盾在外面）：本体换无盾画面、盾心定位点失效。数据干员按积木状态重写（data_operator）
func prop_out() -> bool:
	return false


## 无盾画面（10-15，星熊掷盾后手上还画着盾）：def.sprites.noshield =
##   {"art": {动作: 帧条名}（Codex 无盾帧条，docs/97 H 批；帧数 / 脚底与该动作相同，有图就用），
##    "keep": {动作: [帧号…]}（这些帧本来就没盾，不换），"fallback": {"anim", "frames", "fps"}（没图时改播这个动作里的无盾帧：走动时按 fps 轮换，站着停在最后一帧）}
## 纯画面：只换贴图，不碰玩法状态
func _noshield(st: Dictionary) -> Dictionary:
	if st.is_empty() or not prop_out():
		return st
	var ns = def.get("sprites", {}).get("noshield", null)
	if not (ns is Dictionary):
		return st
	var kind: String = str(st.get("kind", ""))
	var keep = ns.get("keep", {}).get(kind, [])
	if keep is Array and keep.has(int(st.get("frame", -1))):
		return st
	var an: String = str(ns.get("art", {}).get(kind, ""))
	if an != "" and g.tex.get(an) != null:
		var out := st.duplicate()
		out["tex"] = g.tex[an]
		return out
	var fb = ns.get("fallback", {})
	if not (fb is Dictionary):
		return st
	var fk: String = str(fb.get("anim", ""))
	var ftx: Texture2D = anim_tex(fk)
	var frs = fb.get("frames", [])
	if ftx == null or not (frs is Array) or frs.is_empty():
		return st
	var i: int = frs.size() - 1
	if kind == "run":
		i = int(g.t * float(fb.get("fps", 8.0))) % frs.size()
	return {"tex": ftx, "frame": int(frs[i]), "hf": anim_hframes(ftx, fk), "flip": (face < 0.0) != sprite_mirror(fk), "kind": fk}


## ---- 多条技能帧条 + 循环状态（10-16，docs/87 §3.5；首例铃兰）：def.sprites.skills = {"s1": …, "s2": …, "s3": …}（键 = 技能序号 + 1），
## 没写的技能照旧走 skill_anim()（缺省 sprites.skill 单条，其他干员不变）。每个值是下面三种之一：
##   {"anim": 帧条}                                      单条：同 skills[i].anim（出手帧按该条 fire）
##   {"intro": 帧条, "hold": 帧条, "hold_ms": 250}        起手（intro 条第 0 帧，按其 fps 播一帧）→ 定格 hold 条 hold_ms 毫秒 → 待机；出手 = 定格开始
##   {"start": 段, "loop": 帧条, "end": 段}               起手播 start（出手帧按 start 条的 fire）→ 技能生效期间（skill_active_left(i) > 0）loop 循环
##                                                        → 收势播 end → 待机；技能不计时（永久 / 次数型）就跳过 loop 直接收势。end 可省
## 「段」= 帧条名，或 {"anim": 帧条, "frames": [帧号…]}（只播这条里的这几帧，顺序随写）。帧条名是 sprites 的槽名；不是 idle / run / attack / skill 的要列进 extra_sprites（加载）。
## 逻辑窗口（attack_t / fire_t）只由起手段决定（时长 = 起手段帧数 / fps，出手 = fire 帧中点），hold / loop / end 纯画面：技能效果、acting()、
## 充能暂停与原单条口径一致。循环期间起手的别的动作（普攻 / 另一技能）压过循环，播完接着循环；起手 / 收势途中被别的动作打断则序列作废
##   "attack": 帧条（可选，10-16 水月 S2 伞击）：循环期间的普攻画面改播这条（技能期间攻击变体），按它的 fire 帧对齐普攻条的出手时刻
##   （attack_t / fire_t / 朝向等模拟量不动，同 seed 不变），播完回循环；比出手窗口长的部分照播（下一次普攻起手则从头对齐）。
##   没写 attack 槽的照旧用普通 attack 条压过循环。只管 act_anim = "attack" 的普攻；start_attack 指定了别的帧条（anim 参数）的不换
var sq: Dictionary = {}   # 当前序列定义（空 = 不在序列里）
var sq_i := -1            # 序列属于哪个技能
var sq_ph := 0            # 0 无 / 1 起手 / 2 定格或循环 / 3 收势 / 4 纯画面进入
var sq_t := 0.0           # 当前阶段已播秒数
var sq_paused: Array[Dictionary] = []   # 被其他技能序列暂时遮住的持续动作（每个技能至多一份）
var sq_own := false       # 当前出手窗口（attack_t）是序列自己的起手段
var sq_atk := ""          # 循环期间正在播的普攻变体帧条（"" = 没有）
var sq_atk_t := -1.0      # 变体从这次普攻起手算起已播秒数（attack_t 归零后继续走；播完清 sq_atk 但保留计时免得同一次普攻再触发；-1 = 下一次普攻从头对齐）


func skill_seq(i: int) -> Dictionary:
	var v = def.get("sprites", {}).get("skills", {}).get("s%d" % (i + 1), null) if i >= 0 else null
	return v if v is Dictionary else {}


## 「段」的帧条名
static func seq_anim(seg) -> String:
	if seg is Dictionary:
		return str(seg.get("anim", ""))
	return str(seg) if seg != null else ""


## 「段」播的帧号表（没写 frames = 整条）
func _seq_frames(seg, kind: String) -> Array:
	var tx := anim_tex(kind)
	var frs: Array = range(int(sprite_spec(kind).get("frames", anim_hframes(tx, kind) if tx != null else 0)))
	if seg is Dictionary:
		if seg.get("frames") is Array and not seg.frames.is_empty():
			frs = seg.frames.duplicate()
		if bool(seg.get("reverse", false)):
			frs.reverse()
	return frs


## 「段」的时长（秒）
func _seq_len(seg) -> float:
	var k := seq_anim(seg)
	if k == "" or (anim_tex(k) == null and not sprite_spec(k).has("frames")):
		return 0.0
	return frames_seconds(k, _seq_frames(seg, k))


## 起手：按 skills.sN 的类型设出手窗口并进入序列；没定义 / 缺图返回 false（走单条）
func _start_skill_seq(aim: Vector2, i: int) -> bool:
	var q := skill_seq(i)
	if q.is_empty():
		return false
	var hold: bool = q.has("hold")
	var head = q.get("intro" if hold else "start", q.get("anim", null))
	var hk := seq_anim(head)
	if hk == "" or (anim_tex(hk) == null and not sprite_spec(hk).has("frames")):
		return false
	if not hold and not q.has("start"):
		return false   # 只写 anim 的走单条（skill_anim 同义）
	if aim != Vector2.INF and absf(aim.x - pos.x) > FACE_DEAD:
		_set_face(signf(aim.x - pos.x))
	var spec := sprite_spec(hk)
	var fps := float(spec.get("fps", 12.0))
	var frs: Array = [0] if (hold and not (head is Dictionary)) else _seq_frames(head, hk)
	var dur := frames_seconds(hk, frs)
	var fire_at := dur
	if hold:
		dur += float(q.get("hold_ms", 250)) / 1000.0   # 出手 = 定格开始
	else:
		var fi: int = frs.find(int(spec.get("fire", 0)))
		fire_at = float(spec.get("fire_time", (float(fi if fi >= 0 else frs.size() - 1) + 0.5) / fps))
		if spec.has("logic") and frs.size() == int(spec.get("frames", 0)):
			var lw := logic_window(spec)
			dur = lw[0]
			fire_at = lw[1]
	_sq_pause(i)
	sq = q
	sq_i = i
	sq_ph = 1
	sq_t = 0.0
	sq_own = true
	sq_atk = ""
	sq_atk_t = -1.0
	attack_phased = false
	act_kind = "skill"
	act_anim = hk
	attack_dur = dur
	attack_t = dur
	fire_t = fire_at
	anim_kind = hk
	anim_t = 0.0
	return true


## 纯画面版起手（play_vis_skill）：同 _start_skill_seq 的序列状态，但不设出手窗口（attack_t / fire_t / act_* 不动）。
## 起手段仍 sq_own（压过同帧起手的普攻画面，与出手窗口版一致），起手播完 _tick_sq 清掉 sq_own，之后普攻画面压过循环、播完接着循环
func _start_vis_seq(i: int) -> bool:
	var q := skill_seq(i)
	if q.is_empty():
		return false
	var hold: bool = q.has("hold")
	var head = q.get("intro" if hold else "start", null)
	var hk := seq_anim(head)
	if hk == "" or anim_tex(hk) == null:
		return false
	_sq_pause(i)
	sq = q
	sq_i = i
	sq_ph = 1
	sq_t = 0.0
	sq_own = true
	sq_atk = ""
	sq_atk_t = -1.0
	vis_anim = ""
	anim_kind = hk
	anim_t = 0.0
	return true


## 当前阶段的「段」
func _sq_seg():
	match sq_ph:
		1:
			return sq.get("intro" if sq.has("hold") else "start", null)
		2:
			if not sq.has("hold") and sq.has("run"):
				var running: bool = mv > (RUN_EXIT if anim_kind == seq_anim(sq.run) else RUN_ENTER)
				if running and anim_tex(seq_anim(sq.run)) != null:
					return sq.run
			return sq.get("hold" if sq.has("hold") else "loop", null)
		3:
			return sq.get("end", null)
		4:
			return sq.get("enter", null)
	return null


func _sq_kind() -> String:
	if sq_ph == 0:
		return ""
	var k := seq_anim(_sq_seg())
	return k if anim_tex(k) != null else ""


## 当前阶段的帧号：起手 / 收势按帧表播一遍停末帧，定格 / 循环按 fps 循环
func _sq_frame(n: int) -> int:
	var seg = _sq_seg()
	var k := seq_anim(seg)
	var frs: Array = [0] if (sq_ph == 1 and sq.has("hold") and not (seg is Dictionary)) else _seq_frames(seg, k)
	if frs.is_empty():
		return 0
	var elapsed := attack_dur - attack_t if sq_ph == 1 and sq_own and attack_t > 0.0 and act_kind == "skill" and act_anim == k else sq_t
	return clampi(timed_frame(k, frs, elapsed, sq_ph == 2), 0, n - 1)


## 别的动作起手（_start_action）：起手 / 收势途中作废序列；循环 / 定格期间只是暂时被压过
## 锁定序列（json sprites.skills.sN.lock = true）：序列整段（起手 / 持续 / 收势）画面不让给普攻等别的动作，普攻起手也不打断序列（纯显示）
func seq_locked() -> bool:
	return sq_ph != 0 and bool(sq.get("lock", false))


func _sq_interrupt() -> void:
	if sq_ph == 1 or sq_ph == 3:
		_sq_clear()
	sq_own = false
	sq_atk = ""   # 新动作起手：变体作废（普攻会在 follow 里按新的出手窗口重新对齐）
	sq_atk_t = -1.0


func _sq_pause(i: int) -> void:
	for n in range(sq_paused.size() - 1, -1, -1):
		if sq_paused[n].i == i:
			sq_paused.remove_at(n)
	if sq_i != i and sq_ph in [2, 4] and not sq.has("hold"):
		sq_paused.append({"q": sq, "i": sq_i, "ph": sq_ph, "t": sq_t})


func _sq_clear() -> void:
	sq = {}
	sq_i = -1
	sq_ph = 0
	sq_t = 0.0
	sq_own = false
	sq_atk = ""
	sq_atk_t = -1.0
	while not sq_paused.is_empty():
		var saved: Dictionary = sq_paused.pop_back()
		sq = saved.q
		sq_i = int(saved.i)
		if skill_active_left(sq_i) > 0.0:
			sq_ph = int(saved.ph)
			sq_t = float(saved.t)
			return
		if _seq_len(sq.get("end")) > 0.0:
			sq_ph = 3
			return
		sq = {}
		sq_i = -1


## follow() 每帧：推进序列阶段（纯画面）
func _tick_sq(dt: float) -> void:
	if sq_ph == 0:
		return
	var hold: bool = sq.has("hold")
	# 施法后的进入段被其他动作遮住时暂停，不改变那些动作的逻辑窗口。
	if sq_ph != 4 or (attack_t <= 0.0 and vis_anim == ""):
		sq_t += dt
	match sq_ph:
		1:
			var head = sq.get("intro" if hold else "start")
			var n1: float = (1.0 / float(sprite_spec(seq_anim(head)).get("fps", 12.0))) if (hold and not (head is Dictionary)) else _seq_len(head)
			if sq_t >= n1:
				sq_t = 0.0
				if not hold:
					sq_own = false   # start 段结束：出手窗口版此时 attack_t 也正好到 0；纯画面版（play_vis_skill）之后让普攻画面压过循环。hold 的出手窗口覆盖整个定格，保留
				if hold or skill_active_left(sq_i) > 0.0:
					sq_ph = 4 if not hold and _seq_len(sq.get("enter")) > 0.0 else 2
				else:
					_sq_end()
		2:
			if hold:
				if sq_t >= float(sq.get("hold_ms", 250)) / 1000.0:
					_sq_clear()
			elif skill_active_left(sq_i) <= 0.0:
				sq_t = 0.0
				_sq_end()
		4:
			if skill_active_left(sq_i) <= 0.0:
				sq_t = 0.0
				_sq_end()
			elif sq_t >= _seq_len(sq.get("enter")):
				sq_t = 0.0
				sq_ph = 2
		3:
			if sq_t >= _seq_len(sq.get("end")):
				_sq_clear()
	_tick_sq_atk(dt)


## 循环期间的普攻变体（sq.attack）：普攻出手窗口开着（act_anim = "attack"）就从这次起手对齐，attack_t 归零后继续播到末帧再清掉
func _tick_sq_atk(dt: float) -> void:
	var k := _sq_atk_kind()
	if k == "":
		sq_atk = ""
		sq_atk_t = -1.0
		return
	if attack_t > 0.0 and act_kind == "attack" and act_anim == "attack" and not sq_own:
		var el: float = attack_dur - attack_t   # 这次普攻已播秒数
		if sq_atk_t < 0.0 or el < sq_atk_t - 0.0001:
			sq_atk = k   # 新一次普攻：从头对齐（变体比出手窗口短时播完清掉，同一次普攻不再触发）
		sq_atk_t = el
	elif sq_atk != "":
		sq_atk_t += dt
	else:
		return
	if sq_atk == "":
		return
	var spec := sprite_spec(sq_atk)
	var n := float(spec.get("frames", anim_hframes(anim_tex(sq_atk), sq_atk)))
	if (sq_atk_t >= attack_dur) if attack_phased else (sq_atk_t + _sq_atk_off() >= frames_seconds(sq_atk, range(int(n)))):
		sq_atk = ""   # 播完回循环


## 当前序列循环阶段可用的普攻变体帧条（"" = 没写 / 缺图 / 不在循环阶段）
func _sq_atk_kind() -> String:
	if sq_ph != 2 or sq.has("hold"):
		return ""
	var k := seq_anim(sq.get("attack", null))
	return k if k != "" and anim_tex(k) != null else ""


## 变体时间轴相对普攻起手的偏移：变体 fire 帧中点对齐普攻条（attack 槽）的出手时刻；变体时间 = sq_atk_t + 偏移
func _sq_atk_off() -> float:
	var vs := sprite_spec(sq_atk)
	var vfps := float(vs.get("fps", 12.0))
	var v_fire: float = float(vs.get("fire_time", (float(vs.get("fire", 0)) + 0.5) / vfps))
	var a := sprite_spec("attack")
	var a_fire: float = float(a.get("fire_time", (float(a.get("fire", 0)) + 0.5) / float(a.get("fps", 12.0)))) if a.has("fire") else attack_dur * 0.5
	return v_fire - a_fire


func _sq_atk_frame(n: int) -> int:
	if attack_phased:
		return attack_phase_frame(n, int(sprite_spec(sq_atk).get("fire", 0)), sq_atk_t)
	if sprite_spec(sq_atk).has("frame_durations"):
		return timed_frame(sq_atk, range(n), maxf(0.0, sq_atk_t + _sq_atk_off()))
	var fps := float(sprite_spec(sq_atk).get("fps", 12.0))
	return clampi(int(maxf(0.0, sq_atk_t + _sq_atk_off()) * fps), 0, n - 1)


func _sq_end() -> void:
	if _seq_len(sq.get("end")) > 0.0:
		sq_ph = 3
	else:
		_sq_clear()


## 统一序列的影子 [缩放, 不透明度]；序列结束后仍完成回地面的渐变。
var sq_air := 0.0
var sq_shadow := Vector2.ONE

func _tick_sq_shadow(dt: float) -> void:
	if sq_ph != 0:
		sq_shadow = Vector2(float(sq.get("shadow", 1.0)), float(sq.get("shadow_a", 1.0)))
	var up: bool = sq_ph == 2 or sq_ph == 4 or (sq_ph == 1 and not sq.has("enter"))
	sq_air = move_toward(sq_air, 1.0 if up else 0.0, dt / 0.25)

func shadow_k() -> Vector2:
	return Vector2.ONE.lerp(sq_shadow, smoothstep(0.0, 1.0, sq_air))


## 跑步帧率缩放（2026-09-27）：帧条按 RUN_REF 移速画，实际速度按比例加快 / 放慢
const RUN_REF := 150.0
const RUN_K_MIN := 0.6
const RUN_K_MAX := 2.0   # 最高 20fps，再快腿部发糊（runretest P2）
const RUN_ENTER := 40.0
const RUN_EXIT := 20.0
var run_ph := 0.0


## 横向脚底锚点（2026-09-27）：帧条渲染按帧宽居中；foot[0]（1x 像素，该贴图槽的 foot，否则 def.sprites.foot）偏离帧中心时
## 把画的位置反向挪回去，让各动作的脚都落在 pos 上（run / idle 重心不同造成的跑停、转身横跳）。foot[0] = 帧宽 / 2 时为 0
func foot_dx(st: Dictionary, flip = null) -> float:
	var tx: Texture2D = st.get("tex")
	if tx == null:
		return 0.0
	var kind: String = st.get("kind", "")
	var spec := sprite_spec(kind) if kind != "" else {}
	var ft = spec.get("foot", def.get("sprites", {}).get("foot", null))
	if not (ft is Array) or ft.size() < 1:
		return 0.0
	var hires: float = A.hires_of(tx)
	var fw: float = float(tx.get_width()) / float(maxi(1, int(st.get("hf", 1))))
	var off: float = float(ft[0]) * hires - fw / 2.0   # 脚在帧内相对中心的偏移（贴图像素）
	var fl: bool = st.get("flip", false) if flip == null else bool(flip)
	return -off * (g.PX / hires) * (-1.0 if fl else 1.0)


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
		cv.draw_circle(pos, 10.0, Color(0.6, 0.9, 1.0))
		return
	# 残影（动态模糊，用户选定方案 A，2026-09-25）：突然冲刺时身后 3–4 个带职业色的渐隐分身，先画在本体下面
	var c: Color = col().lerp(Color.WHITE, 0.35)
	for gh in ghosts:
		var a: float = GHOST_ALPHA * (1.0 - gh.age / GHOST_LIFE)
		draw_sprite_at(gh.p + Vector2(foot_dx(gh.st), 0), gh.st.flip, Color(c.r * 1.4, c.g * 1.4, c.b * 1.4, a), gh.st.frame, gh.st.tex, gh.st.hf, foot_off(gh.st.tex, gh.st.get("kind", "")))
	if arriving() and arrive_t < ARRIVE_WAIT:
		return   # 换人入场：还在屏幕外等
	if cmd_down > 0.0:
		_draw_downed(st)
		return
	if is_leader and g.state == g.S.DEAD:   # 队长倒下：播本人 death 条，停在末帧（10-22 用户定「倒地」，不用撤退闪白）
		var ds := downed_state(g.state_age)
		if not ds.is_empty():
			st = ds
	# 主控：受击闪白 / 闪红 / 无敌闪烁沿用 game.gd 算好的 sprite.modulate
	var mod: Color = g.sprite.modulate if is_leader else Color.WHITE
	draw_sprite_at(pos + Vector2(foot_dx(st), 0) + Vector2(0, arrive_dy()), st.flip, mod, st.frame, st.tex, st.hf, foot_off(st.tex, st.get("kind", "")))


## 换人入队（10-22 用户定）：等被换下的队友跳出屏幕（ARRIVE_WAIT 秒）后从屏幕上方落到编队位，纯画面（玩法照常从入队起算）。
## arrive_t 由 world.update_visuals 推进，< 0 = 不在入场
const ARRIVE_WAIT := 0.35
const ARRIVE_FALL := 0.35
var arrive_t := -1.0

func arriving() -> bool:
	return arrive_t >= 0.0 and arrive_t < ARRIVE_WAIT + ARRIVE_FALL


## 入场时本体的竖直偏移：等待期间放在屏幕外，下落按二次加速落地
func arrive_dy() -> float:
	if not arriving():
		return 0.0
	var u: float = clampf((arrive_t - ARRIVE_WAIT) / ARRIVE_FALL, 0.0, 1.0)
	return -(1.0 - u * u) * (g.world.view_rect(0.0).size.y + 80.0 * g.PX)


## 突击倒地（docs/114 §7）：播 death 条一遍停在末帧（压暗一点）；还没有 death 条的画躺倒的灰色剪影（待机帧转 90°）
func _draw_downed(st: Dictionary) -> void:
	var dtx: Texture2D = anim_tex("death")
	var foot: Vector2 = pos + g.draw_off
	if dtx != null:
		var n: int = anim_hframes(dtx, "death")
		var fr: int = mini(n - 1, int(cmd_down_age * float(sprite_spec("death").get("fps", ANIM_FPS.death))))
		var ds := {"tex": dtx, "frame": fr, "hf": n, "flip": (face < 0.0) != sprite_mirror("death"), "kind": "death"}
		draw_sprite_at(pos + Vector2(foot_dx(ds), 0), ds.flip, Color(0.75, 0.75, 0.8), fr, dtx, n, foot_off(dtx, "death"))
		return
	_cv_flush()   # 还没有 death 条的（用户 10-22 定倒地统一用 death 条，claude/retreat-to-downed 在补）：先画躺倒的灰色剪影，不再放共用退场闪光
	var tx: Texture2D = st.tex
	var hf: int = maxi(1, int(st.hf))
	var fw: float = float(tx.get_width()) / hf
	var fh: float = float(tx.get_height())
	var pk: float = g.PX / A.hires_of(tx)
	g.draw_set_transform(foot.round(), -PI / 2.0 if not st.flip else PI / 2.0, Vector2(pk, pk))
	g.draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh + foot_off(tx, str(st.get("kind", "")))), Vector2(fw, fh)), Rect2(0, 0, fw, fh), Color(0.55, 0.58, 0.68, 0.9))
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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


## 在别处画一份当前帧（分身 / 残影）：flip = 朝左；帧条带 mirror 标记时在这里取反
func draw_body_at(p: Vector2, flip: bool, col: Color, st: Dictionary = {}) -> void:
	if st.is_empty():
		st = anim_state()
	if st.is_empty():
		return
	flip = flip != sprite_mirror(str(st.get("kind", "")))
	draw_sprite_at(p + Vector2(foot_dx(st, flip), 0), flip, col, st.frame, st.tex, st.hf, foot_off(st.tex, st.get("kind", "")))


## ---- 帧条绘制助手（docs/55 §2.1：原来卡缇 / 流明 / 斯卡蒂各抄一份 _strip，水月 / 铃兰 / 维什戴尔各抄一份 _fx_tex + _fx_strip，10-10 合并到基类）
## 画一帧横向帧条（Codex 成长线 growth_fx，双密度）：anchor_px 按 @1x 帧内像素给，sc 为 @1x 每像素的世界尺寸；
## @2x 贴图自动把倍率减半、锚点加倍（同 game.gd _spr_rot 的口径）
func _strip(tx: Texture2D, frames: int, fr: int, p: Vector2, sc: float, anchor_px: Vector2, flip := false, col := Color.WHITE) -> void:
	var hi: float = A.hires_of(tx)
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	var k: float = sc / hi * float(def.get("sprites", {}).get("draw_scale", 1.0))   # 干员整体缩放（docs/103：水月 0.9 试验，10-16）
	cv.draw_set_transform(p.round(), 0.0, Vector2(-k if flip else k, k))
	cv.draw_texture_rect_region(tx, Rect2(-anchor_px * hi, Vector2(fw, fh)), Rect2(fw * (fr % frames), 0, fw, fh), col)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 可选帧条：首次用到时 A.tex 懒加载并缓存进 g.tex（缺图缓存 null）
func _fx_tex(name: String) -> Texture2D:
	if not g.tex.has(name):
		g.tex[name] = A.tex(name)
	return g.tex[name]


## 帧条贴图（有图画图、缺图返回 false 走程序版）；1 美术像素 = PX 世界像素，@2x 高清帧条按 A.hires_of 半倍画；anchor 为帧内比例锚点
func _fx_strip(name: String, frames: int, frame: int, p: Vector2, anchor := Vector2(0.5, 0.5), ang := 0.0, col := Color.WHITE, flip := false) -> bool:
	var tx: Texture2D = _fx_tex(name)
	if tx == null:
		return false
	var fw: float = float(tx.get_width() / frames)
	var fh: float = float(tx.get_height())
	var k: float = g.PX / A.hires_of(tx)
	cv.draw_set_transform(p.round(), ang, Vector2(-k if flip else k, k))
	cv.draw_texture_rect_region(tx, Rect2(-Vector2(fw, fh) * anchor, Vector2(fw, fh)), Rect2(fw * (frame % frames), 0, fw, fh), col)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## Switch sustained-stage slots only between rounds, retaining the native sequence lifecycle.
func set_attack_phase(stage: Dictionary, transition: bool) -> float:
	sq = sq.duplicate(true)
	for key in ["loop", "attack", "end"]:
		sq[key] = stage[key]
	if not transition:
		return 0.0
	sq_t = 0.0
	play_vis_anim(str(stage.get("transition", "")))
	return vis_dur() if vis_anim != "" else 0.0
