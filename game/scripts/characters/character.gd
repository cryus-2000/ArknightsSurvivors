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
var attack_t := 0.0        # >0 表示正在播放攻击动作（由干员在出手时设置）
var attack_dur := 0.25
# ---- 动画：贴图槽来自 def.sprites（idle / run / attack / hurt / death），帧数 = 宽 / 高
var anim_kind := ""
var anim_t := 0.0
const ANIM_FPS := {"idle": 4.0, "run": 10.0, "hurt": 10.0, "death": 6.0}


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
	validate_skills(cid, inst.skills(), d)
	return inst


## 三技能契约：恰好 3 个核心技能；释放方式只能是 auto / manual，且 manual 最多 1 个。
## 基础攻击与天赋不占槽；技能进阶、E1/E2、藏品只能改造这三个技能，不能新增可施放槽位。
static func validate_skills(cid: String, table: Dictionary, d: Dictionary) -> bool:
	var ids: Array = d.get("skills", table.keys())
	var ok := true
	if ids.size() != 3:
		push_error("角色 %s 必须恰好定义 3 个核心技能，现在是 %d" % [cid, ids.size()])
		ok = false
	var manual := 0
	for sid in ids:
		if not table.has(sid):
			push_error("角色 %s 的技能 %s 没有定义" % [cid, sid])
			ok = false
			continue
		var mode: String = table[sid].get("mode", "auto")
		if mode != "auto" and mode != "manual":
			push_error("角色 %s 技能 %s 的 mode 只能是 auto / manual" % [cid, sid])
			ok = false
		if mode == "manual":
			manual += 1
	if manual > 1:
		push_error("角色 %s 最多只能有 1 个手动技能，现在是 %d" % [cid, manual])
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


# ---------------------------------------------------------------- 数值

## 角色 JSON 的 base 段：专属基础数值（如伞击伤害、挥砍半径），缺项用默认
func base(key: String, default: float) -> float:
	return float(def.get("base", {}).get(key, default))


## 角色专属属性定义（stat 名 -> {base, min, max, name}），带角色前缀
func stat_defs() -> Dictionary:
	return {}


## 属性块有变化时由 game.gd 调用：把 g.stats 里的专属属性同步到角色缓存变量
func sync_stats(_st) -> void:
	pass


## 普攻半径（自动索敌 / 机器人走位用）
func _swing_radius() -> float:
	return 90.0


## 伤害通用倍率（天赋等）
func _dmg_bonus() -> float:
	return g.dmg_mult


# ---------------------------------------------------------------- 成长 / 技能 / 精英化

## 成长项生效
func _apply_growth(_gid: String) -> void:
	pass


## 升级卡上的数值预览
func _growth_preview(_gid: String) -> String:
	return ""


## 技能发动演出（技能自动触发时由角色内部调用）
func _skill_cast(_sid: String) -> void:
	pass


## 精英化一：可选路线 id 列表
func evo_paths() -> Array:
	return def.get("evo", {}).get("paths", [])


## 精英化二：某路线下的质变 id 列表
func evo_mutations(path: String) -> Array:
	return def.get("evo", {}).get("mutations", {}).get(path, [])


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


# ---------------------------------------------------------------- 跟随与动画（squad.gd 调用）

## 跟随博士的编队位：近处慢慢挪、远处快步跟上；离得太远（开局 / 传送）直接归位
func follow(dt: float, target: Vector2) -> void:
	if pos == Vector2.INF or pos.distance_to(target) > 700.0:
		pos = target
		mv = 0.0
		return
	var prev: Vector2 = pos
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
	mt += dt
	# 动画状态
	var want := "idle"
	if attack_t > 0.0 and anim_tex("attack") != null:
		want = "attack"
	elif mv > 30.0 and anim_tex("run") != null:
		want = "run"
	if want != anim_kind:
		anim_kind = want
		anim_t = 0.0
	anim_t += dt


## 干员面向某个方向（出手时由干员调用）
func face_to(ang: float) -> void:
	face = 1.0 if cos(ang) >= 0.0 else -1.0


func facing_angle() -> float:
	return 0.0 if face >= 0.0 else PI


## 贴图槽：def.sprites[kind] 的贴图名 → g.tex；没有就返回 null
func anim_tex(kind: String) -> Texture2D:
	var sp: Dictionary = def.get("sprites", {})
	if not sp.has(kind):
		return null
	return g.tex.get(sp[kind])


func anim_hframes(tx: Texture2D) -> int:
	return max(1, tx.get_width() / tx.get_height())


## 当前帧（贴图 / 帧序号 / 帧数），残影 / 分身等复用
func anim_state() -> Dictionary:
	var tx: Texture2D = anim_tex(anim_kind)
	if tx == null:
		tx = anim_tex("idle")
	if tx == null:
		return {}
	var n: int = anim_hframes(tx)
	var fr := 0
	match anim_kind:
		"attack":
			fr = clampi(int(anim_t / attack_dur * n), 0, n - 1)
		_:
			fr = int(anim_t * float(ANIM_FPS.get(anim_kind, 4.0))) % n
	return {"tex": tx, "frame": fr, "hf": n, "flip": face < 0.0}


## 脚底锚点在帧内的位置（def.sprites.foot，默认帧底部上方 2px）
func foot_off(tx: Texture2D) -> float:
	var sp: Dictionary = def.get("sprites", {})
	var hires: float = A.hires_of(tx)
	if sp.has("foot"):
		return (tx.get_height() - float(sp.foot[1]) * hires)
	return 2.0 * hires


## 画干员本体（世界坐标，脚底在 pos）
func draw_body() -> void:
	var st := anim_state()
	if st.is_empty():
		g.draw_circle(pos, 10.0, Color(0.6, 0.9, 1.0))
		return
	g._draw_sprite_at(pos, st.flip, Color.WHITE, st.frame, st.tex, st.hf, foot_off(st.tex))


## 在别处画一份当前帧（分身 / 残影）
func draw_body_at(p: Vector2, flip: bool, col: Color, st: Dictionary = {}) -> void:
	if st.is_empty():
		st = anim_state()
	if st.is_empty():
		return
	g._draw_sprite_at(p, flip, col, st.frame, st.tex, st.hf, foot_off(st.tex))
