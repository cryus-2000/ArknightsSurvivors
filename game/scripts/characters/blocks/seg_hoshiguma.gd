## 干员积木 · seg_hoshiguma（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/ob_hw.gd"


# ================================================================ 星熊 hoshiguma（docs/59 §3，docs/61「星熊」节）：格挡 / 反击 / 击退 / 直线斩 / 地面区域
## 第一位用到这些积木的是星熊，积木本身是通用的（任何数据干员都能写）。后来的干员追加积木：另起自己的段落，把名字登进 EXT_BLOCKS / EXT_CONDS，
## 校验写进 _ext_block 的 match，执行写进 data_operator.gd 末尾对应的段落。
## 确定性：只有 trig.on_hurt 的概率用 g.rng，且只在该触发器生效、概率在 (0, 1) 之间时才取数（不带这些积木的干员一个随机数都不多取）。

## 族.名 → 放置类别：instant = 瞬时（技能 do、触发器 do、区域 do）；sustain = 常驻（技能 do、passive do、成长节点）；
## skill = 只能放技能 do；trig = 触发积木（trait / talent / 成长节点）
const EXT_BLOCKS := {
	"shape.line": "instant",          # 直线斩：从自身朝最近目标（手动普攻按 A 方向）长 len、宽 width 的矩形，命中沿线全部
	# verb.displace / verb.field 与安洁莉娜共用，合并时统一到文件末尾「共用积木」段（SHARED_TAGS）
	"verb.negate_next": "skill",      # 技能持续期间，主控下一次受到的攻击完全格挡（on_block）；持续结束仍没挨打则执行 on_miss
	"verb.dr": "sustain",             # 主控受到的伤害 × (1 - value)（经 dmg_taken_mult）
	"verb.negate_chance": "sustain",  # 本干员带 negate 的 trig.on_hurt 概率：(chance + Σadd) × Πmult
	"verb.swap_attack": "sustain",    # 生效期间普攻换成 attack 里的形状（节奏仍按 blocks.attack.every）
	"trig.on_hurt": "trig",           # 主控将受到一次攻击（闪避 / 护盾之后）：chance / boss_chance 概率执行 do；negate = 这一下完全格挡
	"trig.on_negate": "trig",         # 本干员格挡了一次攻击（negate_next 或带 negate 的 on_hurt）
}


static func ext_kind(tag: String) -> String:
	return str(EXT_BLOCKS.get(tag, ""))


static func ext_cond_true(o, k: String) -> bool:
	match k:
		"beacon_charging":
			return o.g.beacon_sys != null and o.g.beacon_sys.charging != null
	return false


## trig.on_hurt 的生效概率：Boss 来源有 boss_chance 时用它；negate 触发器再吃 verb.negate_chance 的 add / mult；夹到 [0, max_chance]
static func hurt_chance(t: Dictionary, boss: bool, add: float, mul: float) -> float:
	var p: float = float(t.get("chance", 1.0))
	if boss and t.has("boss_chance"):
		p = float(t.boss_chance)
	if t.get("negate", false):
		p = (p + add) * mul
	return clampf(p, 0.0, float(t.get("max_chance", 1.0)))


## 概率判定：0 / 1 不取随机数（确定性：概率为常数 1 的触发器不改变 g.rng_op 序列）
static func roll(g, p: float) -> bool:
	if p >= 1.0:
		return true
	if p <= 0.0:
		return false
	return g.rng_op.randf() < p


## shape.line：返回命中列表。伤害口径同 exec_shape（base[atk_key] × mult × 局部 dmg × _dmg_bonus [× skill_power]，精英 / Boss × vs_elite）；
## 击退沿斩击方向；画面走通用 fx（中心 = 线段中点，半径 = 半长，例：fit 32 = 原「按 len / 64 缩放」）
static func exec_line(o, b: Dictionary) -> Array:
	var g = o.g
	var L: float = float(b.get("len", 0.0)) * o.stat(&"op_range")
	var W: float = float(b.get("width", 40.0))
	var ts: Array = o.nearest_enemies(1, L + 20.0, o.pos)
	var ang: float = o.atk_angle((ts[0].pos - o.pos).angle() if not ts.is_empty() else o.facing_angle())
	var d := Vector2.from_angle(ang)
	var hits: Array = []
	for j in o.query_ids(o.pos + d * L * 0.5, L * 0.5 + W + 40.0):
		var e: Dictionary = g.enemies[j]
		if not e.dead and line_contains(o.pos, d, L, W, e.pos, float(e.r)):
			hits.append(e)
	var max_n: int = int(b.get("max_n", 0))
	if max_n > 0 and hits.size() > max_n:
		hits = o.cap_targets(hits, o.pos, max_n)
	var dmg: float = o.base(str(b.get("atk_key", "atk")), 0.0) * float(b.get("mult", 1.0)) * float(o.loc.dmg) * o._dmg_bonus()
	if b.get("power", false):
		dmg *= o.skill_power()
	dmg *= el_atk_mult(o)   # 精英化段：普攻（含 swap_attack 换上的直线斩）吃局部倍率 atk
	var src: String = str(b.get("src", ""))
	var tags: Array = b.get("tags", [])
	var kb: float = float(b.get("kb", 0.0))
	var stun: float = float(b.get("stun", 0.0))
	var ve: float = o.vs_elite()
	for e in hits:
		o.log_hit(src, tags)
		o.deal_damage(e, dmg * (ve if e.elite or e.boss else 1.0))
		if e.dead or e.boss:
			continue
		if kb > 0.0:
			o.apply_kb(e, d * kb * (0.3 if e.elite else 1.0))
		if stun > 0.0:
			o.add_cc(e, stun * (0.5 if e.elite else 1.0))
	for e in hits:
		o._hit_fx(e, o.pos)
	for s in b.get("on_hit", _EA):
		for e in hits:
			apply_status(o, e, s)
	# 画面：通用 fx（docs/61 §5.6）以线段中点为中心、半长为半径、斩击方向为角度（rot: true 随方向转）；没有 fx 或缺图时画一道程序线
	if fx_any_tex(o, b.get("fx", [])):
		fx_play(o, b.fx, o.pos + d * L * 0.5, L * 0.5, hits, ang)
	else:
		var fy := Vector2(0, -12.0)
		o.fx({"kind": "line", "pos": o.pos + fy, "to": o.pos + d * L + fy, "life": 0.18, "col": o.col(), "w": W * 0.3})
	return hits


## 瞬时区域 / 位移的中心：self（缺省）/ leader / target（调用方给的点：区域 tick、落点、on_kill 的敌人、on_hurt 的主控）/ zone（本干员区域中心）/
## last_hit（本干员上一次普攻命中的第一个敌人）
static func field_center(o, b: Dictionary, at: Vector2 = Vector2.INF) -> Vector2:
	match str(b.get("center", "self")):
		"leader":
			return o.g.ppos
		"target":
			return at
		"zone":
			return o.zone_c()
		"last_hit":
			return o.last_hit_pos
	return o.pos


## 新积木的放置与参数校验（_block 认出 EXT_BLOCKS 里的名字后转到这里）
static func _ext_block(b: Dictionary, p: String, kind: String, tag: String, xk: String, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	var ok_place := false
	match kind:
		"attack":
			ok_place = tag.begins_with("shape.") and xk == "instant"
		"trig":
			ok_place = xk == "trig"
		"instant":
			ok_place = xk == "instant"
		"sustain":
			ok_place = xk == "sustain"
		"skill":
			ok_place = xk in ["instant", "sustain", "skill"]
	if not ok_place:
		var kn: String = {"instant": "瞬时", "sustain": "常驻", "skill": "只能放技能 do", "trig": "触发积木"}.get(xk, xk)
		errs.append("%s：「%s」（%s）不能放在这里（%s）" % [p, tag, kn, kind])
		return
	match tag:
		"shape.line":
			_num(b, "len", p, ctx, true, 10.0, 800.0)
			_num(b, "width", p, ctx, true, 4.0, 300.0)
			_num(b, "mult", p, ctx, false, -INF, 20.0)
			_num(b, "max_n", p, ctx, false, 1.0, 99.0)
			_num(b, "kb", p, ctx, false, 0.0)
			_num(b, "stun", p, ctx, false, 0.0, 10.0)
			_src(b, p, ctx, true)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
		"verb.negate_next":
			_list(b.get("on_block", []), p + ".on_block", "instant", ctx)
			_list(b.get("on_miss", []), p + ".on_miss", "instant", ctx)
		"verb.dr":
			_num(b, "value", p, ctx, true, 0.0, 0.9)
		"verb.negate_chance":
			if not (b.has("add") or b.has("mult")):
				errs.append(p + "：verb.negate_chance 要写 add / mult 之一")
			_num(b, "add", p, ctx, false, -1.0, 1.0)
			_num(b, "mult", p, ctx, false, 0.0, 5.0)
		"verb.swap_attack":
			var a = b.get("attack", null)
			if not (a is Dictionary) or not str(a.get("shape", "")) in ["circle", "cone", "line"]:
				errs.append(p + ".attack 必须是一个伤害形状（shape.circle / shape.cone / shape.line）")
			else:
				_block(a, p + ".attack", "attack", ctx)
		"trig.on_hurt":
			_num(b, "chance", p, ctx, false, 0.0, 1.0)
			_num(b, "boss_chance", p, ctx, false, 0.0, 1.0)
			_num(b, "max_chance", p, ctx, false, 0.0, 1.0)
			_num(b, "cd", p, ctx, false, 0.0)
			if b.has("negate") and not (b.negate is bool):
				errs.append(p + ".negate 只能是 true / false")
			_list(b.get("do", []), p + ".do", "instant", ctx)
		"trig.on_negate":
			_list(b.get("do", []), p + ".do", "instant", ctx)
