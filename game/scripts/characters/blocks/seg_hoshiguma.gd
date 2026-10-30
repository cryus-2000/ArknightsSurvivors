## 干员积木 · seg_hoshiguma（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/ob_hw.gd"


# ================================================================ 星熊 hoshiguma（docs/59 §3，docs/61「星熊」节）：格挡 / 反击 / 击退 / 直线斩 / 地面区域
## 第一位用到这些积木的是星熊，积木本身是通用的（任何数据干员都能写）。后来的干员追加积木：另起自己的段落，把名字登进 EXT_BLOCKS / EXT_CONDS，
## 校验写进 _ext_block 的 match，执行写进 data_operator.gd 末尾对应的段落。
## 确定性：只有 trig.on_hurt 的概率用 g.rng，且只在该触发器生效、概率在 (0, 1) 之间时才取数（不带这些积木的干员一个随机数都不多取）。

## 族.名 → 放置类别：instant = 瞬时（技能 do、触发器 do、区域 do）；sustain = 常驻（技能 do、passive do、成长节点）；
## skill = 只能放技能 do；trig = 触发积木（trait / talent / 成长节点）
const EXT_BLOCKS := {
	"shape.line": "instant",          # 直线斩：从自身朝最近目标（按住瞄准按 A 方向）长 len、宽 width 的矩形，命中沿线全部
	# verb.displace / verb.field 与安洁莉娜共用，合并时统一到文件末尾「共用积木」段（SHARED_TAGS）
	"verb.negate_next": "skill",      # 技能持续期间，主控下一次受到的攻击完全格挡（on_block）；持续结束仍没挨打则执行 on_miss
	"verb.taunt_guard": "skill",      # 10-24 星熊 S1（docs/140）：技能持续期间本干员站定（是队长时照常走）、把半径 r 内近战杂兵的仇恨拉到自己身上；
	                                  # 结束时执行 on_end，其中伤害形状的倍率 + per × min(期间拉到的不同敌人数, cap)
	"verb.dr": "sustain",             # 主控受到的伤害 × (1 - value)（经 dmg_taken_mult）
	"verb.negate_chance": "sustain",  # 本干员带 negate 的 trig.on_hurt 概率：(chance + Σadd) × Πmult
	"verb.swap_attack": "sustain",    # 生效期间普攻换成 attack 里的形状（节奏仍按 blocks.attack.every）
	"trig.on_hurt": "trig",           # 主控将受到一次攻击（闪避 / 护盾之后）：chance / boss_chance 概率执行 do；negate = 这一下完全格挡
	"trig.on_negate": "trig",         # 本干员格挡了一次攻击（negate_next 或带 negate 的 on_hurt）
	# ---- docs/202 成长节点（10-29）新积木：星熊 / 德克萨斯 / 能天使共用这一段登记（执行在各自的段文件，注释里标出）
	"trig.on_hit_n": "trig",          # 普攻一次命中 ≥ n 个敌人（exec_any_shape 之后）；do 里的积木读 o.gm_hits（这一次命中列表）；星熊 / 德克萨斯
	"verb.block_mark": "instant",     # 星熊「阻挡」：命中里离她最近的 n 名被阻挡 dur 秒（减速 + 不绕过她）
	"verb.force_block": "instant",    # 星熊「般若之重」：队长的下一次受击必定被格挡（dur 秒内有效，cd 秒内至多武装一次）
	"verb.boil_sand": "instant",      # 星熊「热砂·沸腾」：命中站在热砂里的敌人 → 该处热砂立刻结算剩余伤害的 frac 并熄灭，溅一圈火星
	"verb.dash_cd_cut": "instant",    # 德克萨斯「居合」：每名命中缩短队长冲刺冷却 per 秒（每次出手至多 max 秒）
	"verb.break_windup": "instant",   # 德克萨斯「破绽」：命中的普通敌人正在前摇出招 → 打断 + 小击退（无眩晕；精英 / Boss 除外）
	"verb.aim_prefer": "sustain",     # 能天使「对空优先」：子弹优先瞄准受控目标，命中即停并追加定身 pin 秒
	"verb.escort": "sustain",         # 能天使「护航射击」：队长 r 内敌人 ≥ n 时子弹改打离队长最近的，击退 +kb
	"verb.tracer": "sustain",         # 能天使「曳光弹」：每 every 发一枚曳光弹，命中标记 secs 秒，队友对标记目标伤害 +bonus
	# docs/202 成长节点 · 拉普兰德（blocks/seg_lappland.gd）
	"verb.ll_dial_arm": "instant",    # 日晷·反斩：记一次反斩待命（下一道剑气变大剑气）
	"verb.ll_dial_swing": "instant",  # 待命还没被剑气用掉 → 执行 do（额外掷一道大剑气）并清除待命
	"verb.ll_riposte": "instant",     # 日晷·回敬：朝最近的敌人原地反斩（r / half / mult / kb / cd / src / slash_fx）
	"verb.ll_seal_spread": "instant", # 断喝·传染（on_kill 的 do）：刚死的被封印者把封印扩散出去（r / n / dur）
}


static func ext_kind(tag: String) -> String:
	return str(EXT_BLOCKS.get(tag, ""))


static func ext_cond_true(o, k: String) -> bool:
	match k:
		"beacon_charging":
			return o.g.beacon_sys != null and o.g.beacon_sys.charging != null
		"roaming":   # 指挥「突击」中的队友（character.is_roaming；10-26 突击模式低频自冲刺：德克萨斯 json 的 dash_line）
			return o.is_roaming()
		"enemy_near":   # 普攻范围（形状半径 + 30，同起手的找目标半径）内有敌人（德克萨斯疾刃三连：没有敌人就照常两连斩，10-23）
			return not o.nearest_enemies(1, shape_radius(o, o.cur_attack()) + 30.0, o.pos).is_empty()
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
		"verb.taunt_guard":
			_num(b, "r", p, ctx, true, 20.0, 600.0)
			_num(b, "per", p, ctx, false, 0.0, 2.0)
			_num(b, "cap", p, ctx, false, 1.0, 200.0)
			_num(b, "dur", p, ctx, false, 0.5, 20.0)
			_num(b, "elite_x", p, ctx, false, 0.0, 1.0)
			_num(b, "stop", p, ctx, false, 0.0, 0.3)
			_list(b.get("on_end", []), p + ".on_end", "instant", ctx)
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
		"trig.on_hit_n":
			_num(b, "n", p, ctx, true, 1.0, 20.0)
			_list(b.get("do", []), p + ".do", "instant", ctx)
		"verb.block_mark":
			_num(b, "n", p, ctx, true, 1.0, 8.0)
			_num(b, "dur", p, ctx, true, 0.1, 10.0)
			_num(b, "slow", p, ctx, true, 0.0, 0.9)
		"verb.force_block":
			_num(b, "dur", p, ctx, true, 0.5, 30.0)
			_num(b, "cd", p, ctx, true, 0.5, 60.0)
			_num(b, "ring_r", p, ctx, false, 10.0, 400.0)
		"verb.boil_sand":
			_num(b, "frac", p, ctx, true, 0.0, 1.0)
			_num(b, "spark_r", p, ctx, true, 10.0, 300.0)
			_num(b, "spark_mult", p, ctx, false, 0.0, 5.0)
		"verb.dash_cd_cut", "verb.break_windup", "verb.aim_prefer", "verb.escort", "verb.tracer":
			_gm_validate(b, p, ctx, tag)


# ================================================================ docs/202 成长节点（10-29）：星熊「阻挡」「般若之重」「热砂·落刃」「热砂·沸腾」
## 状态 o.gm（空 = 用不到）：blk 阻挡 {敌人 id: {e, t 到期 g.t}}、force_until 武装到期、force_cd 下次可武装。
## 确定性：全部不取随机数；画面只用 o.fx（pfx）和 draw_entities_floor 里的程序图形，不碰 g.rng。
const GM_BLOCK_MAX := 6        # 同时被阻挡的敌人上限（节点 n=3，留余量给 S1 之外的叠加）

## 校验（德克萨斯 / 能天使积木的参数检查转到各自段文件，用 _F() 前向调用）
static func _gm_validate(b: Dictionary, p: String, ctx: Dictionary, tag: String) -> void:
	match tag:
		"verb.dash_cd_cut", "verb.break_windup":
			_F()._tx_gm_validate(b, p, ctx, tag)
		_:
			_F()._exu_gm_validate(b, p, ctx, tag)


## exec_any_shape（普攻出手）之后：记下这一次的命中列表，执行命中 ≥ n 的 trig.on_hit_n
static func gm_hit_n(o, hits: Array) -> void:
	o.gm_hits = hits
	for t in o._trigs():
		if str(t.get("_tag", "")) != "trig.on_hit_n" or hits.size() < int(t.get("n", 1)) or not cond_true(o, t.get("cond", _ED)):
			continue
		o._exec_list(t.get("do", []), hits[0].pos)


## 阻挡：命中里离她最近的至多 n 名（已被阻挡的占名额但不刷新）。减速 slow（精英 ×0.5，Boss 不吃）+ dur 秒内近战杂兵改追她（不绕过她，gm_tick 每帧重标）
static func gm_block_mark(o, b: Dictionary) -> void:
	var live: Array = []
	for e in o.gm_hits:
		if not e.dead:
			live.append(e)
	if live.is_empty():
		return
	live.sort_custom(func(x, y):
		var dx: float = x.pos.distance_squared_to(o.pos)
		var dy: float = y.pos.distance_squared_to(o.pos)
		return dx < dy if dx != dy else int(x.id) < int(y.id))
	var gm: Dictionary = o.gm
	var blk: Dictionary = gm.get("blk", {})
	var take: int = mini(int(b.n), live.size())
	for i in take:
		var e: Dictionary = live[i]
		if blk.has(int(e.id)) and float(blk[int(e.id)].t) > o.g.t:
			continue   # 已被阻挡：只占名额，不刷新
		if e.boss or blk.size() >= GM_BLOCK_MAX:
			continue
		var k: float = 0.5 if e.elite else 1.0
		var dur: float = float(b.dur) * k
		o.g.enemies_sys.lite_slow(e, float(b.slow) * k, dur)
		blk[int(e.id)] = {"e": e, "t": o.g.t + dur}
		o.fx({"kind": "ring", "pos": e.pos, "r": float(e.r) + 16.0, "r0": float(e.r), "life": 0.3, "col": Color(1.0, 0.85, 0.4), "floor": true, "w": 2.5, "alpha": 0.9})
	gm["blk"] = blk


## 阻挡每帧（_ext_sustain 末尾调）：到期 / 死亡的清掉；还在的近战杂兵本帧改追她（set_aggro 每帧重标）
static func gm_tick(o) -> void:
	var blk: Dictionary = o.gm.get("blk", {})
	if blk.is_empty():
		return
	var gone: Array = []
	for id in blk:
		var r: Dictionary = blk[id]
		var e: Dictionary = r.e
		if e.dead or float(r.t) <= o.g.t:
			gone.append(id)
		elif e.ai == "melee" and not e.chest:
			o.set_aggro(e, o.pos)
	for id in gone:
		blk.erase(id)


## 般若之重：武装「队长下一次受击必定格挡」。cd 内不再武装；dur 秒内没人打队长就作废
static func gm_force_block(o, b: Dictionary) -> void:
	var gm: Dictionary = o.gm
	if float(gm.get("force_cd", 0.0)) > o.g.t:
		return
	gm["force_until"] = o.g.t + float(b.dur)
	gm["force_cd"] = o.g.t + float(b.cd)
	o.fx({"kind": "ring", "pos": o.g.ppos, "r": 44.0, "r0": 12.0, "life": 0.35, "col": Color(1.0, 0.85, 0.4), "floor": true, "w": 3.0, "alpha": 0.9})
	o.fx({"kind": "ring", "pos": o.pos, "r": float(b.get("ring_r", 90.0)), "r0": 20.0, "life": 0.45, "col": Color(1.0, 0.8, 0.3), "floor": true, "w": 6.0, "alpha": 0.95})   # 盾面压地的冲击环
	o.ground_dust(o.pos, float(b.get("ring_r", 90.0)) * 0.6, 10)
	o.float_text(o.g.ppos + Vector2(0, -100), "般若之重", Color(1.0, 0.85, 0.4), 14)


## 受击询问（dmg_taken_mult 开头）：武装中 → 用掉并返回 true（本次必定格挡）
static func gm_force_take(o) -> bool:
	var gm: Dictionary = o.gm
	if float(gm.get("force_until", 0.0)) <= o.g.t:
		return false
	gm["force_until"] = 0.0
	return true


## 热砂·沸腾：命中的敌人若站在带 sand 标记的热砂里，该处热砂立刻结算剩余伤害的 frac 并熄灭，在热砂中心溅一圈火星（半径 spark_r）
static func gm_boil_sand(o, b: Dictionary) -> void:
	if o.fields.is_empty():
		return
	for f in o.fields:
		if not f.get("sand", false) or f.done >= f.n:
			continue
		var hit := false
		for e in o.gm_hits:
			if not e.dead and e.pos.distance_to(f.pos) <= float(f.r) + float(e.r):
				hit = true
				break
		if not hit:
			continue
		var rem: float = float(f.n - f.done)
		var scaled: Array = []
		for x in f.do:
			var y: Dictionary = x.duplicate()
			if y.has("mult"):
				y.mult = float(y.mult) * rem * float(b.frac)
			scaled.append(y)
		f.done = f.n   # 熄灭（_ext_sustain 本帧收掉）
		o._exec_list(scaled, f.pos)
		if float(b.get("spark_mult", 0.0)) > 0.0:
			o._exec_list([{"_tag": "shape.circle", "shape": "circle", "center": "target", "r": float(b.spark_r), "mult": float(b.spark_mult), "src": "热砂沸腾", "tags": ["skill"], "power": true}], f.pos)
		o.fx({"kind": "ring", "pos": f.pos, "r": float(b.spark_r), "r0": 8.0, "life": 0.35, "col": Color(1.0, 0.45, 0.2), "floor": true, "w": 4.0, "alpha": 0.95})
		for k in 8:
			var a: float = TAU * float(k) / 8.0 + 0.2
			o.sparks(f.pos, Vector2.from_angle(a), Color(1.0, 0.6, 0.25), 2, 120.0)


## 画面（draw_entities_floor 末尾调）：被阻挡的敌人脚下一枚金色盾形小印；般若之重武装时队长脚下一圈金环；热砂外缘一圈橙色椭圆（带「沸腾」时更亮）
static func gm_draw(o) -> void:
	var cv = o.cv
	for f in o.fields:
		if not f.get("sand", false):
			continue
		var fa: float = clampf((float(f.n) * float(f.every) - float(f.t)) / 0.4, 0.0, 1.0)
		var sf: float = o.ring_flash("sand%d" % int(f.pos.x * 7.0 + f.pos.y))   # 10-31 TA H1：外缘椭圆只在铺开那一瞬
		if sf <= 0.0:
			continue
		var hot: float = 0.25 + (0.2 * (0.5 + 0.5 * sin(o.g.t * 7.0)) if o.tags_all.has("verb.boil_sand") else 0.0)
		cv.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.5))
		cv.draw_arc(Vector2.ZERO, float(f.r), 0.0, TAU, 32, Color(1.0, 0.55, 0.2, (hot * fa + 0.15 * fa) * sf), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var blk: Dictionary = o.gm.get("blk", {})
	for id in blk:
		var r: Dictionary = blk[id]
		var e: Dictionary = r.e
		if e.dead:
			continue
		var a: float = clampf((float(r.t) - o.g.t) / 0.4, 0.0, 1.0)
		var c: Vector2 = e.pos + Vector2(0, 6)
		var w: float = float(e.r) * 0.9 + 6.0
		var pts := PackedVector2Array([c + Vector2(-w, -w * 0.5), c + Vector2(w, -w * 0.5), c + Vector2(w * 0.8, w * 0.4), c + Vector2(0, w), c + Vector2(-w * 0.8, w * 0.4)])
		cv.draw_colored_polygon(pts, Color(1.0, 0.82, 0.35, 0.42 * a))
		cv.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1.0, 0.9, 0.5, 1.0 * a), 2.0)
	if float(o.gm.get("force_until", 0.0)) > o.g.t and o.g.ppos != Vector2.INF:
		var k: float = 0.8 * o.ring_flash("force")   # 10-31 TA H1：武装那一瞬亮一下，不常驻
		cv.draw_set_transform(o.g.ppos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		cv.draw_arc(Vector2.ZERO, 36.0, 0.0, TAU, 32, Color(1.0, 0.82, 0.35, k), 3.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)



# ================================================================ 星熊 S1「战意」重斩画面（用户 10-31：重斩的表现补上、技能圈去掉）
## 只画画面（借终结技框架 g.ult 的 strip / 灯 / 颗粒，g.ult 关时不画）：沉重下劈弧光（pixgen 3 种新月弧 fx_hs_arc1–3）→ 落点爆亮 + 暖灰金分叉裂网
## （fx_hs_fork，乌尔比安裂缝转色）一节节往外长、先亮后冷 → 地块顶起落回 + 尘 → 0.25 秒余震；卡肉沿用 s1_stop 命中顿帧，另加一下轻震。
## 变体：每次按出手时刻 + 位置的哈希挑弧光、转角、裂缝条数 / 角度 / 长短 / 镜像、碎块飞向，同种子同局可重现，不抽模拟随机数。
## 嘲讽信号：被拉过来的敌人头上闪一下金色「!」（不画圈）。
const HS_ARCS := ["fx_hs_arc1", "fx_hs_arc2", "fx_hs_arc3"]
const HS_FORK := "fx_hs_fork"
const HS_ROCK := "fx_ul_rock"
const HS_GOLD := Color(1.0, 0.86, 0.55)
const HS_COLD := Color(0.24, 0.2, 0.16)


static func _hh(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 78.233) * 43758.5453, 1.0)


static func s1_slash_fx(o, b: Dictionary) -> void:
	var u = o.g.ult
	if u == null or not u.fx_ready(HS_ARCS[0]):
		return
	var g = o.g
	var p0: Vector2 = o.pos
	var vs: float = floorf(_hh(g.t * 1.37 + p0.x * 0.013 + p0.y * 0.029) * 997.0)
	var R: float = float(o.base("s1_r", 150.0)) * o.stat(&"op_range")
	var fx: float = -1.0 if float(o.face) < 0.0 else 1.0
	var fd := Vector2(fx, 0.18 * (_hh(vs + 1.0) - 0.3)).normalized()   # 朝面向、略往下劈
	# ① 下劈弧光：新月弧凸向前方，缩放缓出 + 爆亮冷却；后面一道淡残影
	var arc: String = HS_ARCS[int(_hh(vs) * 3.0) % 3]
	var t: Texture2D = u._strip_tex(arc)
	var hw: float = t.get_height()
	var sc: float = R * 1.25 / maxf(1.0, hw / 2.0 * g.PX)   # 弧高约 1.25 R
	var ang: float = fd.angle() + (_hh(vs + 2.0) - 0.5) * 0.35
	var sy: float = -1.0 if _hh(vs + 3.0) < 0.5 else 1.0
	var ac: Vector2 = p0 + fd * R * 0.3 + Vector2(0, -18)
	u.strip(arc, ac - fd * 20.0, {"ang": ang - 0.35 * fx, "sc": sc * 0.92, "sy": sy, "life": 0.14, "fade": 0.12, "col": Color(1, 1, 1, 0.35)})
	u.strip(arc, ac, {"ang": ang, "sc": sc * 0.85, "sc1": sc * 1.05, "scd": 0.06, "sy": sy, "life": 0.22, "fade": 0.14,
		"col": Color(1.05, 1.02, 0.95, 0.85), "col1": Color(0.45, 0.55, 0.45, 0.9), "cold": 0.2})
	# ② 落点：爆亮 + 灯 + 轻震
	var P: Vector2 = p0 + fd * R * 0.55
	u.shape({"kind": "circle", "c": P, "r": 34.0, "col": Color(0.95, 0.88, 0.7), "fill": 0.85, "life": 0.07})
	u.light(P, R * 1.5, Color(0.75, 0.62, 0.38), 0.2)
	u.shake(3.0, 0.12)
	# ③ 裂网：5–7 条分叉裂缝从落点外跑，角度 / 长短 / 粗细 / 镜像按哈希错开，暖金爆亮冷成暗灰
	if u.fx_ready(HS_FORK):
		var ft: Texture2D = u._strip_tex(HS_FORK)
		var fw: float = ft.get_width() / 2.0 * g.PX
		var n: int = 5 + int(_hh(vs + 4.0) * 3.0)
		for j in n:
			var a: float = fd.angle() + TAU * (float(j) + (_hh(vs + j * 1.7) - 0.5) * 0.8) / n
			var L: float = R * (0.55 + 0.6 * _hh(vs + j * 2.9))
			u.strip(HS_FORK, P + Vector2.from_angle(a) * 10.0, {"layer": "back", "ang": a, "o": Vector2(0.0, ft.get_height() * 0.5), "sx": L / fw,
				"sy": (0.7 if _hh(vs + j * 3.3) < 0.35 else 0.45) * (-1.0 if _hh(vs + j * 4.1) < 0.5 else 1.0), "rev": 0.14, "rev0": 0.15,
				"delay": 0.03 * _hh(vs + j), "life": 1.2, "fade": 0.5, "col": HS_GOLD, "col1": HS_COLD, "cold": 0.5})
	# ④ 地块顶起落回 + 尘；0.25 秒余震再跳一批
	if u.fx_ready(HS_ROCK):
		for q in 7:
			var hq: float = _hh(vs + q * 5.3)
			var dv := Vector2.from_angle(TAU * (q + hq) / 7.0)
			var high: bool = q % 3 == 0
			_s1_rock(u, P + dv * R * (0.3 + 0.35 * hq), dv * (70.0 if high else 25.0), (300.0 if high else 130.0) + 60.0 * hq, hq, 0.32 if high else 0.25, 0.04)
		for q in 4:
			var hq2: float = _hh(vs + q * 9.1 + 50.0)
			_s1_rock(u, P + Vector2.from_angle(TAU * hq2) * R * (0.2 + 0.5 * _hh(hq2 * 7.0)), Vector2.ZERO, 120.0, hq2, 0.24, 0.25 + 0.04 * q)
	for q in 8:
		var dq := Vector2.from_angle(TAU * (q + _hh(vs + q)) / 8.0)
		u.grain("bfx_dust", P + dq * R * 0.35, dq, Color(0.6, 0.56, 0.5), 3)


static func _s1_rock(u, p: Vector2, v: Vector2, vy: float, hh: float, sc: float, delay: float) -> void:
	var fr: Array = [0, 1, 3]
	var grav: float = 1500.0
	u.strip(HS_ROCK, p, {"f": int(fr[int(hh * 97.0) % 3]), "sc": sc + 0.15 * _hh(hh * 17.0), "sx": -1.0 if _hh(hh * 29.0) < 0.5 else 1.0,
		"v": v + Vector2(0, -vy), "grav": grav, "life": 2.0 * vy / grav, "spin": (hh - 0.5) * 9.0, "delay": delay, "col": Color(1.1, 1.02, 0.92)})


## 嘲讽信号：这名敌人刚被拉过来——头上闪一下金色「!」（竖条 + 点，往上弹一点就淡掉）
static func s1_taunt_mark(o, p: Vector2) -> void:
	var u = o.g.ult
	if u == null:
		return
	var top: Vector2 = p + Vector2(0, -34)
	u.shape({"kind": "line", "a": top, "b": top + Vector2(0, -12), "w": 3.0, "col": HS_GOLD, "life": 0.35, "v": Vector2(0, -30)})
	u.shape({"kind": "circle", "c": top + Vector2(0, 5), "r": 2.0, "col": HS_GOLD, "fill": 1.0, "life": 0.35, "v": Vector2(0, -30)})
