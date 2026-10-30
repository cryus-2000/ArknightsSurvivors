## 干员积木 · ob_summon（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/ob_vortex.gd"

const SummonVisual = preload("res://scripts/characters/summon_visual.gd")
const VisGrowth = preload("res://scripts/characters/blocks/vis_growth.gd")
const M3 = preload("res://scripts/characters/blocks/m3_hp.gd")   # Mon3tr 血条 / 倒下 / 复活 / 治疗分配（10-29）   # 可见成长（docs/163）：召唤物体型 / 持续时间


# ================================================================ 召唤 / 封印 / 护盾 / 治疗光环（docs/61 §15，10-12 通用积木，下一批干员备用）
# 通用积木，现在还没有正式干员用（测试专用干员 tests/data_ops/sstest.json 演示全部写法）。核心部分只加了几处转发：
# validate 认 blocks.summons 段、_block 里 SM_TAGS 命中时转给 _sm_block、apply_status 的 st.seal 绕开「Boss 缺省不受」（Boss 有自己的规则）。
# data_operator.gd 对应的转发都标了「召唤 / 封印段」；运行时状态在干员的 sm 字典（不放 ext：ext 非空会被能天使段当成用得到）。
# 游戏侧挂点（敌人一侧，封印读 e.seal_t）：run/enemies.gd 2 处（特殊招式 pattern、远程开火）、boss_ai.gd 1 处（Boss 出招 ready）、
# run/combat.gd 2 处（甲壳 / 潮盾词条失效）+ 1 处（受击询问 dmg_taken_mult(src, dmg) 传这一下的伤害，护盾用）。没有封印 / 护盾时这些分支都不走，老干员逐字节不变。
#
#  verb.summon  瞬时：召唤 n 个 kind（写在 blocks.summons.<kind>）的召唤物。at：self（缺省）/ leader / target / zone；spread 散开半径；life 可覆盖种类的 life
#  st.seal      命中状态（on_hit / 力场 tick）：封印 dur 秒——非 Boss 敌人不起新的特殊招式（enemy_ai 的 pattern：冲刺 / 吐酸 / 环弹 / 神经光环 / 额外招式……）、
#               不远程开火、甲壳 / 潮盾词条失效；已经起手的蓄力照常打完。精英 × elite_mult；
#               Boss：时长 × boss_mult、封顶 boss_max 秒，期间不起新招（冷却照走 = 推迟下一招），封印结束后 boss_immune 秒免疫
#  verb.shield  瞬时：主控护盾 + pct × 最大生命（总量封顶 cap × 最大生命），dur 秒后消失，每秒按当前量衰减 decay；吸收在减伤（verb.dr）之后、护甲 / 法抗之前
#  verb.mark    常驻（10-25 拉普兰德 S3「噤声」）：生效期间本干员每造成一次伤害给那名敌人叠 1 层（keep 秒没再被打就清零），叠满 n 层清零并以该敌人为
#               target 执行 on_full（on_full 自己的伤害不叠层）；画面：层数 = 敌人脚下细银圈逐层加粗，叠满时灰白定格 + 灰白冲击波 + 碎片，
#               ring_r > 0 时开场从脚下扩出静默圈、圈内失色（post.gdshader zone_*，本人保留颜色，低画质不去色）；同屏最多 max_show 名（离本干员近的优先）。技能结束层数全清。只读写本干员的 sm，不取随机数
#  aura.heal    常驻：scope in_zone（缺省，主控在本干员区域内）/ always，每秒回复主控 pct × 最大生命（× 局部 heal 倍率 [× 技能强度]）；满血时不治

const SM_TAGS := ["verb.summon", "st.seal", "verb.shield", "aura.heal", "verb.mark"]

const SM_MOVES := ["orbit", "chase", "stay", "follow"]

const SM_TARGETS := ["nearest", "densest", "elite", "low_hp"]

const SM_AT := ["self", "leader", "target", "zone", "rest"]   # rest：escort 召唤物的闲时站位（§15.9）

const SM_KIND_KEYS := ["name", "hp", "hp_k", "on_down", "invuln", "life", "cap", "r", "col", "move", "attack", "on_spawn", "on_expire", "body", "enemy_target", "decoy_r", "hurt_mult", "_doc"]

const SM_MOVE_KEYS := ["mode", "speed", "anchor", "leash", "orbit_r", "orbit_speed", "target"]

const SM_BODY_KEYS := ["strip", "frames", "fps", "scale", "anchor", "tint", "flip", "hover"]

const SM_TOTAL_CAP := 24      # 全编队同时在场的召唤物上限（性能：每个召唤物 = 一个 2.5D 排序条目 + 一次贴图 / 几何绘制）

const SM_KIND_CAP := 12       # 每种召唤物 cap 的上限（校验）

const SM_FAR := 900.0         # 离锚点超过这么远（主控冲刺 / 传送）直接拉回锚点

const SM_GOLD := 2.39996      # 黄金角：召唤落点 / 围攻站位的确定性散布（不取随机数）

const SEAL_COL := Color(0.66, 0.45, 1.0)

const SHIELD_COL := Color(0.55, 0.9, 1.0)


static func sm_st(o) -> Dictionary:
	if o.sm.is_empty():
		o.sm.merge({"list": [], "seq": 0, "ang": {}, "seal": {}, "shield": 0.0, "shield_max": 0.0, "shield_t": 0.0, "shield_decay": 0.0, "heal_acc": {}})
	return o.sm


static func sm_kind(o, k: String) -> Dictionary:
	return o.B.get("summons", _ED).get(k, {})


## 全编队在场的召唤物数（SM_TOTAL_CAP 用）
static func sm_total(o) -> int:
	var sq = o.g.get("squad")
	if sq == null or not (o in sq.ops):
		return o.sm.get("list", []).size()
	var n := 0
	for m in sq.ops:
		var s = m.get("sm")
		if s is Dictionary and s.has("list"):
			n += s.list.size()
	return n


## 瞬时积木（data_operator._exec_list 的缺省分支转来）
static func sm_exec(o, b: Dictionary, at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"verb.summon":
			sm_spawn(o, b, at)
		"verb.shield":
			shield_add(o, b)


# ---------------------------------------------------------------- 召唤物

## 召唤：每个召唤物 {id, kind, pos, face, t, life（< 0 不限时）, skill（life: skill 时绑定的技能序号）, hp, max_hp, inv, tgt, cd, anim, rt, hurt, flash, gone}
static func sm_spawn(o, b: Dictionary, at: Vector2) -> void:
	var g = o.g
	var kind: String = str(b.get("kind", ""))
	var kd := sm_kind(o, kind)
	if kd.is_empty():
		return
	var st := sm_st(o)
	var c := Vector2.INF
	match str(b.get("at", "self")):
		"leader":
			c = g.ppos
		"target":
			c = at
		"zone":
			c = o.zone_c()
		"rest":
			c = mf_rest(o, kd.get("move", {}))
		_:
			c = o.pos
	if c == Vector2.INF:
		c = g.ppos
	if c == Vector2.INF:
		return
	var lv = b.get("life", kd.get("life", 0.0))
	var life := -1.0
	var sk := -1
	if lv is String:
		if lv == "skill":
			sk = o.cur_skill
	elif float(lv) > 0.0:
		life = float(lv)
	var n: int = int(b.get("n", 1))
	var spread: float = float(b.get("spread", 28.0))
	var cap: int = int(kd.get("cap", 1))
	var hp: float = float(kd.get("hp", 0.0))
	for k in n:
		var same: Array = st.list.filter(func(q): return q.kind == kind)
		if same.size() >= cap:
			_sm_end(o, same[0], "cap")   # 同种超过 cap：最早的先到期（也执行 on_expire）
		if sm_total(o) >= SM_TOTAL_CAP:
			break
		st.seq += 1
		var a: float = float(st.seq) * SM_GOLD
		var rr: float = spread * (0.5 + 0.5 * float(k + 1) / float(n))
		var p: Vector2 = c + Vector2(cos(a) * rr, sin(a) * rr * 0.55)
		var esc: bool = str(kd.get("move", _ED).get("mode", "")) == "escort"
		if esc and n == 1:
			p = c   # 随行召唤物：就站在落点（rest 时 = 闲时站位）
		var s := {"id": int(st.seq), "kind": kind, "pos": p, "face": 1.0 if esc else float(o.face), "t": 0.0, "life": life, "skill": sk,
			"hp": hp, "max_hp": maxf(1.0, hp), "inv": bool(kd.get("invuln", false)), "tgt": null, "cd": float(kd.get("attack", _ED).get("first", 0.25)), "anim": 0.0, "rt": 0.0,
			"hurt": {}, "flash": 0.0, "gone": false}
		if esc and kd.has("hp_k") and not M3.on():
			s.inv = true   # 总开关 kaltsit/m3_hp = 0：回旧行为（Mon3tr 无敌）
		if esc:   # 召唤物扩展段（§15.9）的状态：动画、出手动作、绕行、追击队列、patch、残影、画面计时
			s.merge({"mv": 0.0, "ak": "idle", "at": 0.0, "act": 0.0, "fire": -1.0, "flip_t": -99.0, "via": Vector2.INF, "via_t": 0.0, "via_off": -99.0,
				"pend": [], "pidx": -1, "pt": 0.0, "pout": 0.0, "pold": -1, "pcur": {}, "ghost": {}, "fxt": {}, "swing": 1.0, "cmd_t": 0.0})
			M3.init(o, s, kd)   # 血条：写了 hp_k 且开关开才有血量（否则仍无敌）
		elif kd.has("anim") or kd.has("zone"):   # 精英化第 5 批段：非随行召唤物的帧条状态（浮现 / 待机 / 移动 / 施放）、自带区域
			_F().e5_spawn_state(o, s, kd)
		st.list.append(s)
		o.fx({"kind": "ring", "pos": p, "r": float(kd.get("r", 10.0)) * 2.4, "r0": 4.0, "life": 0.35, "col": _sm_col(o, kd), "floor": true, "w": 2.0, "alpha": 0.8, "keep": true})
		if b.has("fx"):
			fx_play(o, b.fx, p, float(kd.get("r", 10.0)) * 2.0)
		o._exec_list(kd.get("on_spawn", []), p)


static func _sm_col(o, kd: Dictionary) -> Color:
	var cv = kd.get("col", [])
	if cv is Array and cv.size() >= 3:
		return Color(float(cv[0]), float(cv[1]), float(cv[2]))
	return o.col()


## 一个召唤物结束（why：life / skill / dead / cap / leave）：移出列表，leave 以外执行 on_expire（中心 target = 召唤物位置）
static func _sm_end(o, s: Dictionary, why: String) -> void:
	if s.gone:
		return
	SummonVisual.cancel(s)
	s.gone = true
	o.sm.list.erase(s)
	var kd := sm_kind(o, str(s.kind))
	o.fx({"kind": "ring", "pos": s.pos, "r": float(kd.get("r", 10.0)) * 2.0, "r0": float(kd.get("r", 10.0)), "life": 0.3, "col": _sm_col(o, kd), "floor": true, "w": 2.0, "alpha": 0.6, "keep": true})
	if why != "leave":
		o._exec_list(kd.get("on_expire", []), s.pos)


## 干员离队 / 局结束：清掉召唤物（不执行 on_expire）、护盾、封印标记
static func sm_clear(o) -> void:
	if o.sm.is_empty():
		return
	for s in o.sm.list.duplicate():
		_sm_end(o, s, "leave")
	o.sm.shield = 0.0
	o.sm.seal = {}


static func _sm_anchor(o, mv: Dictionary) -> Vector2:
	var p: Vector2 = o.pos if str(mv.get("anchor", "leader")) == "self" else o.g.ppos
	return p if p != Vector2.INF else o.g.ppos


## 攻击距离（世界像素）：写了 range 用 range × op_range；否则按形状（circle 以自身为心 = r，以目标为心 = 40；cone = r；line = len）
static func sm_reach(o, a: Dictionary) -> float:
	if a.is_empty():
		return 0.0
	var k: float = o.stat(&"op_range")
	if a.has("range"):
		return float(a.range) * k
	match str(a.get("shape", "")):
		"circle":
			return float(a.get("r", 30.0)) * k if str(a.get("center", "self")) == "self" else 40.0 * k
		"line":
			return float(a.get("len", 60.0)) * k
	return float(a.get("r", 30.0)) * k


## 能当目标：活着、不是友方单位、不是宝箱
static func _sm_ok(e) -> bool:
	return e != null and not e.dead and not e.get("friendly", false) and not e.chest


static func _hp_frac(e: Dictionary) -> float:
	return float(e.hp) / maxf(1.0, float(e.maxhp))


## 选目标（chase）：锚点 leash 内。nearest = 离召唤物最近（同伴已盯上的往后排，分散开；含 Boss 优先，同 nearest_enemies）；
## densest = 敌群最密处最近的；elite = Boss → 精英 → 其余（同档近的先，cap_targets 的顺序）；low_hp = 生命比例最低（同比例按 id）。全部确定性，不取随机数
static func _sm_pick(o, s: Dictionary, mv: Dictionary, anc: Vector2, leash: float):
	var g = o.g
	var taken := {}
	for q in o.sm.list:
		if q != s and q.tgt != null:
			taken[int(q.tgt.id)] = true
	var cand: Array = []
	var how: String = str(mv.get("target", "nearest"))
	match how:
		"densest":
			var dp: Vector2 = o.densest_point(leash, anc)
			if dp == Vector2.INF:
				return null
			cand = o.nearest_enemies(1, 60.0, dp)
		"elite", "low_hp":
			for j in o.query_ids(anc, leash):
				var e: Dictionary = g.enemies[j]
				if _sm_ok(e) and e.pos.distance_to(anc) <= leash:
					cand.append(e)
			if how == "elite":
				cand = o.cap_targets(cand, s.pos, 6)
			else:
				cand.sort_custom(func(x, y): return _hp_frac(x) < _hp_frac(y) if _hp_frac(x) != _hp_frac(y) else int(x.id) < int(y.id))
		_:
			for e in o.nearest_enemies(6, leash * 2.0, s.pos):
				if e.pos.distance_to(anc) <= leash:
					cand.append(e)
	cand = cand.filter(func(e): return _sm_ok(e))
	if cand.is_empty():
		return null
	for e in cand:
		if not taken.has(int(e.id)):
			return e
	return cand[0]


## 每帧（data_operator.update 在能天使段之后调）：护盾计时、封印标记清理、召唤物到期 / 移动 / 出手 / 诱饵
static func sm_tick(o, dt: float) -> void:
	if o.sm.is_empty():
		return
	var g = o.g
	var st: Dictionary = o.sm
	if float(st.shield) > 0.0:
		st.shield_t = float(st.shield_t) - dt
		if st.shield_t <= 0.0:
			st.shield = 0.0
			sm_shield_pop(o)   # docs/202 歌蕾蒂娅「深海的庇护·反震」：到期也算
		else:
			st.shield = maxf(0.0, float(st.shield) * (1.0 - float(st.shield_decay) * dt))
	if not st.seal.is_empty():
		for id in st.seal.keys():
			var se: Dictionary = st.seal[id]
			if se.dead or float(se.get("seal_t", 0.0)) <= g.t:
				st.seal.erase(id)
	if st.list.is_empty():
		return
	var cnt := {}
	for s in st.list:
		cnt[s.kind] = int(cnt.get(s.kind, 0)) + 1
	for k in cnt:
		var mv: Dictionary = sm_kind(o, k).get("move", {})
		st.ang[k] = fposmod(float(st.ang.get(k, 0.0)) + float(mv.get("orbit_speed", 1.6)) * dt, TAU)
	var idx := {}
	var ends: Array = []
	for s in st.list.duplicate():   # 出手可能击杀 → on_kill → 再召唤，遍历副本
		if s.gone:
			continue
		var kd := sm_kind(o, s.kind)
		s.t += dt
		s.flash = maxf(0.0, float(s.flash) - dt)
		if float(s.life) > 0.0 and s.t >= float(s.life):
			ends.append([s, "life"])
			continue
		if int(s.skill) >= 0 and not o.skill_on(int(s.skill)):
			ends.append([s, "skill"])
			continue
		if not s.inv and float(s.hp) <= 0.0 and not s.has("m3"):
			ends.append([s, "dead"])
			continue
		var i: int = int(idx.get(s.kind, 0))
		idx[s.kind] = i + 1
		if str(kd.get("move", _ED).get("mode", "")) == "escort":
			if s.has("m3") and M3.tick(o, s, kd, dt, mf_rest(o, kd.get("move", _ED))):
				continue   # 倒地中：不移动不出手（读秒、复活都在 M3.tick）
			mf_step(o, s, kd, dt)   # 召唤物扩展段（§15.9）：随行召唤物
		elif s.has("e5"):
			_F().e5_step(o, s, kd, i, int(cnt.get(s.kind, 1)), dt)   # 精英化第 5 批段：带帧条 / 区域的召唤物（内部照样走 _sm_step）
		else:
			_sm_step(o, s, kd, i, int(cnt.get(s.kind, 1)), dt)
	for en in ends:
		_sm_end(o, en[0], en[1])


static func _sm_step(o, s: Dictionary, kd: Dictionary, i: int, n: int, dt: float) -> void:
	var mv: Dictionary = kd.get("move", {})
	var mode: String = str(mv.get("mode", "follow"))
	var anc := _sm_anchor(o, mv)
	var a: Dictionary = kd.get("attack", {})
	var reach := sm_reach(o, a)
	if s.pos.distance_to(anc) > SM_FAR:
		s.pos = anc
		s.tgt = null
	var tg = s.tgt
	if tg != null and not _sm_ok(tg):
		tg = null
	var orr: float = float(mv.get("orbit_r", 60.0 if mode == "orbit" else 44.0))
	var sa: float = PI * 0.5 + TAU * i / maxf(1.0, n)
	var slot: Vector2 = anc + Vector2(cos(sa) * orr, sin(sa) * orr * 0.55)
	var want: Vector2 = s.pos
	match mode:
		"orbit":
			var an: float = float(o.sm.ang.get(s.kind, 0.0)) + TAU * i / maxf(1.0, n)
			want = anc + Vector2(cos(an) * orr, sin(an) * orr * 0.55)
			tg = null
		"follow":
			want = slot
			tg = null
		"stay":
			tg = null
		_:   # chase
			var leash: float = float(mv.get("leash", 240.0))
			if tg != null and tg.pos.distance_to(anc) > leash + 40.0:
				tg = null
			if mv.has("repick"):   # 精英化第 5 批段：每 repick 秒重新选一次目标（densest = 跟着敌群最密处走）
				s["rp"] = float(s.get("rp", 0.0)) - dt
				if float(s.rp) <= 0.0:
					s.rp = float(mv.repick)
					tg = null
					s.rt = 0.0
			s.rt = float(s.rt) - dt
			if tg == null and s.rt <= 0.0:
				tg = _sm_pick(o, s, mv, anc, leash)
				if tg == null:
					s.rt = 0.25   # 没目标时每 0.25 秒再找（大群里不每帧排序）
			if tg != null:
				var ga: float = float(s.id) * SM_GOLD
				want = tg.pos + Vector2(cos(ga), sin(ga) * 0.55) * (float(tg.r) + maxf(8.0, reach * 0.6))
			else:
				want = slot
	s.tgt = tg
	var prev: Vector2 = s.pos
	s.pos = s.pos.move_toward(want, float(mv.get("speed", 240.0)) * dt)
	var vx: float = s.pos.x - prev.x
	if absf(vx) > 0.5:
		s.face = signf(vx)
	# 诱饵：近战杂兵改追它（同骑士 / 海嗣分身的 e.aggro，每帧重标）；有生命的诱饵挨贴身接触伤害（每个敌人 1 秒一次）
	if str(kd.get("enemy_target", "ignore")) == "decoy":
		_sm_decoy(o, s, kd)
	# 出手
	s.cd = float(s.cd) - dt
	s.anim = maxf(0.0, float(s.anim) - dt)
	if a.is_empty() or s.cd > 0.0:
		return
	var t2 = tg
	if t2 == null:
		var ts: Array = o.nearest_enemies(1, reach + 30.0, s.pos)
		t2 = ts[0] if not ts.is_empty() else null
	if not _sm_ok(t2) or s.pos.distance_to(t2.pos) > reach + float(t2.r):
		return
	s.cd = float(a.get("every", 1.0)) / maxf(0.05, o.stat(&"op_aspd"))
	sm_strike(o, s, a, t2)


static func _sm_decoy(o, s: Dictionary, kd: Dictionary) -> void:
	var g = o.g
	var dr: float = float(kd.get("decoy_r", 160.0))
	var br: float = float(kd.get("r", 10.0))
	for j in o.query_ids(s.pos, dr):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.chest or e.boss or e.ai != "melee" or e.pos.distance_to(s.pos) > dr:
			continue
		o.set_aggro(e, s.pos)
	if s.inv:
		return
	var hm: float = float(kd.get("hurt_mult", 0.4))
	for j in o.query_ids(s.pos, br + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.chest or e.dmg <= 0.0 or e.ai != "melee" or e.get("coma", false) or e.get("under", false) or e.get("dormant", false):
			continue
		if e.pos.distance_to(s.pos) > float(e.r) + br or float(s.hurt.get(e.id, -1.0)) > g.t:
			continue
		s.hurt[e.id] = g.t + 1.0
		s.hp = float(s.hp) - float(e.dmg) * hm
		s.flash = 0.15
	if s.hurt.size() > 48:
		for k in s.hurt.keys():
			if float(s.hurt[k]) <= g.t:
				s.hurt.erase(k)


## 召唤物出手：已有形状（circle / cone / line）以召唤物为原点。伤害 = 本干员 base[atk_key] × mult × 局部 dmg × _dmg_bonus（含 op_atk）[× 技能强度]，
## 精英 / Boss × vs_elite；来源 src 记在本干员名下，tags 自动加 summon；on_hit 状态（含 st.seal）照常；画面走通用 fx（中心 = 判定中心）
static func sm_dmg(o, a: Dictionary) -> float:
	var dmg: float = o.base(str(a.get("atk_key", "atk")), 0.0) * float(a.get("mult", 1.0)) * float(o.loc.dmg) * o._dmg_bonus()
	return dmg * o.skill_power() if a.get("power", false) else dmg


static func sm_strike(o, s: Dictionary, a: Dictionary, tg: Dictionary) -> Array:
	var g = o.g
	var dmg: float = sm_dmg(o, a)
	var src: String = str(a.get("src", ""))
	var tags: Array = a.get("tags", []).duplicate()
	if not "summon" in tags:
		tags.append("summon")
	var kb: float = float(a.get("kb", 0.0))
	var stun: float = float(a.get("stun", 0.0))
	var max_n: int = int(a.get("max_n", 0))
	var kr: float = o.stat(&"op_range")
	var ang: float = (tg.pos - s.pos).angle()
	if absf(tg.pos.x - s.pos.x) > 2.0:
		s.face = signf(tg.pos.x - s.pos.x)
	s.anim = 0.22
	var hits: Array = []
	var c: Vector2 = s.pos
	var r: float = float(a.get("r", 30.0)) * kr * VisGrowth.summon_reach(g)   # 可见成长 #130：攻击覆盖与体型同步放大（summon_r_follow）
	match str(a.get("shape", "circle")):
		"cone":
			hits = o.melee_hit(src, s.pos, ang, deg_to_rad(float(a.get("half_deg", 45.0))), r, dmg, kb, stun, tags, max_n)
		"line":
			var L: float = float(a.get("len", 60.0)) * kr
			var W: float = float(a.get("width", 20.0))
			var d := Vector2.from_angle(ang)
			for j in o.query_ids(s.pos + d * L * 0.5, L * 0.5 + W + 40.0):
				var e: Dictionary = g.enemies[j]
				if not e.dead and line_contains(s.pos, d, L, W, e.pos, float(e.r)):
					hits.append(e)
			if max_n > 0 and hits.size() > max_n:
				hits = o.cap_targets(hits, s.pos, max_n)
			var ve: float = o.vs_elite()
			for e in hits:
				o.log_hit(src, tags)
				o.deal_damage(e, dmg * (ve if e.elite or e.boss else 1.0))
				if not e.dead and not e.boss and kb > 0.0:
					o.apply_kb(e, d * kb * (0.3 if e.elite else 1.0))
				if not e.dead and not e.boss and stun > 0.0:
					o.add_cc(e, stun * (0.5 if e.elite else 1.0))
			c = s.pos + d * L * 0.5
			r = L * 0.5
		_:
			if str(a.get("center", "self")) == "target":
				c = tg.pos
			hits = o.area_hit(src, c, r, dmg, kb, stun, tags, max_n)
	for stt in a.get("on_hit", _EA):
		for e in hits:
			apply_status(o, e, stt)
	if a.has("fx") and fx_any_tex(o, a.fx):
		fx_play(o, a.fx, c, r, hits, ang)
	else:
		var cc: Color = _sm_col(o, sm_kind(o, str(s.kind)))
		o.fx({"kind": "ring", "pos": c, "r": maxf(10.0, r * 0.8), "r0": 4.0, "life": 0.2, "col": cc, "floor": true, "w": 2.0, "alpha": 0.7})
	return hits


## 节点「清创」（wide_arc，凯尔希，docs/202；由 _mf_claw 在每次爪击命中后调用）：Mon3tr 的爪击在同一名敌人身上累积 clear_n 次（clear_win 秒内）后，该敌人身上爆开一圈
## （半径 clear_r，Mon3tr 攻击 clear_mult 的真实伤害，来源「Mon3tr · 清创」）并清空累积。一次爪击最多触发 2 处爆开（爆开本身不计累积）
static func sm_debride(o, hits: Array) -> void:
	var g = o.g
	var need: int = int(o.base("clear_n", 3.0))
	var win: float = o.base("clear_win", 4.0)
	var booms: Array = []
	for e in hits:
		if e.dead:
			continue
		var n: int = (int(e.get("m3_cl", 0)) if g.t - float(e.get("m3_clt", -99.0)) <= win else 0) + 1
		e["m3_clt"] = g.t
		if n >= need and booms.size() < 2:
			e["m3_cl"] = 0
			booms.append(e)
		else:
			e["m3_cl"] = mini(n, need - 1)
			var c: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.5)   # 累积 1 / 2 次：身上留一道（两道）爪痕
			for q in n:
				var off: float = (q - (n - 1) * 0.5) * 5.0
				o.fx({"kind": "line", "pos": c + Vector2(off - 5.0, -6.0), "to": c + Vector2(off + 5.0, 6.0), "life": 0.5, "col": Color(1.0, 0.45, 0.35), "w": 1.5})
	var r: float = o.base("clear_r", 70.0)
	for e in booms:
		var dmg: float = sm_dmg(o, {"atk_key": "m_atk", "mult": o.base("clear_mult", 0.4), "power": true})
		o.area_hit("Mon3tr · 清创", e.pos, r, dmg, 0.0, 0.0, ["summon"])
		var c2: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.4)
		o.fx({"kind": "ring", "pos": e.pos, "r": r, "r0": 10.0, "life": 0.3, "col": Color(1.6, 0.15, 0.12), "floor": true, "keep": true, "w": 3.0})
		o.fx({"kind": "glow", "pos": c2, "r": r * 0.6, "life": 0.22, "col": Color(2.0, 0.3, 0.15), "alpha": 0.6})
		for k in 8:
			o.fx({"kind": "spark", "pos": c2, "vel": Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(90.0, 190.0), "life": 0.32, "col": Color(1.7, 0.25, 0.15), "sz": 2.5})


## 2.5D 排序条目（data_operator.extra_bodies）
static func sm_bodies(o) -> Array:
	var out: Array = []
	if o.sm.is_empty():
		return out
	for s in o.sm.list:
		out.append({"y": s.pos.y + 4.0, "s": s})
	return out


## 影子（squad.draw_shadows 的合批画布里）
static func sm_shadows(o) -> void:
	if o.sm.is_empty():
		return
	for s in o.sm.list:
		if mf_shadow(o, s, sm_kind(o, str(s.kind))):   # 召唤物扩展段：影子贴图
			continue
		var r: float = float(sm_kind(o, str(s.kind)).get("r", 10.0))
		o.cv.draw_set_transform(s.pos + Vector2(0, 2), 0.0, Vector2(1.0, 0.4))
		o.cv.draw_circle(Vector2.ZERO, r * 1.1, Color(0, 0, 0, 0.28))
		o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 画一个召唤物（data_operator.draw_extra）：body.strip 帧条（按脚底锚点、随朝向翻转、可悬浮起伏）；缺图时画程序体（圆身 + 眼睛 + 出手前扑）
static func sm_draw(o, s: Dictionary) -> void:
	var g = o.g
	if g.perf_alt and s.has("e5"):   # 精英化第 5 批段：--perfab 的 /b 桶不画（量净成本用）
		return
	var kd := sm_kind(o, str(s.kind))
	if kd.has("anim") and mf_draw(o, s, kd):   # 召唤物扩展段：按状态的帧条（缺图时往下画程序体）
		return
	var body: Dictionary = kd.get("body", {})
	var hov: float = float(body.get("hover", 0.0))
	var p: Vector2 = s.pos + Vector2(0, -hov + (sin(g.t * 3.5 + float(s.id)) * 2.0 if hov > 0.0 else 0.0))
	var al: float = clampf(float(s.t) / 0.15, 0.0, 1.0)
	if float(s.life) > 0.0:
		al *= clampf((float(s.life) - float(s.t)) / 0.3, 0.0, 1.0)
	var lunge := Vector2(float(s.face) * 4.0 * sin(clampf(float(s.anim) / 0.22, 0.0, 1.0) * PI), 0)
	var tint := Color.WHITE
	var tv = body.get("tint", [])
	if tv is Array and tv.size() >= 3:
		tint = Color(float(tv[0]), float(tv[1]), float(tv[2]), float(tv[3]) if tv.size() > 3 else 1.0)
	if float(s.flash) > 0.0:
		tint = tint.lerp(Color(1.6, 1.6, 1.6, tint.a), 0.6)
	tint.a *= al
	var name: String = str(body.get("strip", ""))
	var tx: Texture2D = g.tex.get(name) if name != "" else null
	if tx != null:
		var spec: Array = g.V6_FRAMES.get(name, [])
		var frames: int = maxi(1, int(body.get("frames", spec[0] if spec.size() > 0 else 1)))
		var fps: float = maxf(1.0, float(body.get("fps", spec[1] if spec.size() > 1 else 8)))
		var fr: int = int(float(s.t) * fps) % frames
		var h: float = ArtS.hires_of(tx)
		var fw: int = tx.get_width() / frames
		var fh: int = tx.get_height()
		var an := Vector2(fw * 0.5, fh)
		var av = body.get("anchor", [])
		if av is Array and av.size() == 2:
			an = Vector2(float(av[0]), float(av[1])) * h
		var sc: float = g.PX * float(body.get("scale", 1.0)) * VisGrowth.summon_scale(g)
		var fl: float = -1.0 if body.get("flip", true) and float(s.face) < 0.0 else 1.0
		o._cv_flush()
		o.cv.draw_set_transform(p + lunge, 0.0, Vector2(fl * sc / h, sc / h))
		o.cv.draw_texture_rect_region(tx, Rect2(-an, Vector2(fw, fh)), Rect2(fw * fr, 0, fw, fh), tint)
		o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		var r: float = float(kd.get("r", 10.0)) * VisGrowth.summon_scale(g)
		var cc: Color = _sm_col(o, kd)
		var q: Vector2 = p + lunge + Vector2(0, -r)
		o.cv.draw_circle(q, r + 1.5, Color(0.03, 0.03, 0.06, 0.8 * al))
		o.cv.draw_circle(q, r, Color(cc.r * tint.r, cc.g * tint.g, cc.b * tint.b, al))
		o.cv.draw_circle(q + Vector2(-r * 0.25, -r * 0.3), r * 0.45, Color(minf(cc.r * 1.5, 1.5), minf(cc.g * 1.5, 1.5), minf(cc.b * 1.5, 1.5), 0.5 * al))
		var ex: float = float(s.face) * r * 0.45
		o.cv.draw_circle(q + Vector2(ex, -r * 0.15), maxf(1.5, r * 0.18), Color(1.0, 0.95, 0.85, al))
	if not s.inv and float(s.hp) < float(s.max_hp):
		var w: float = 18.0
		var bp: Vector2 = s.pos + Vector2(-w * 0.5, -hov - float(kd.get("r", 10.0)) * 2.0 - 8.0)
		o.cv.draw_rect(Rect2(bp, Vector2(w, 2.5)), Color(0.05, 0.05, 0.08, 0.8 * al))
		o.cv.draw_rect(Rect2(bp, Vector2(w * clampf(float(s.hp) / float(s.max_hp), 0.0, 1.0), 2.5)), Color(0.5, 1.0, 0.6, al))


# ---------------------------------------------------------------- 封印 st.seal

## 一名敌人吃封印（apply_status 转来；Boss 规则在这里，不走「Boss 缺省不受」）。
## e.seal_t = 封印结束的 g.t；e.seal_imm = Boss 免疫结束的 g.t；e.seal_by = 施加者 id（画标记用）
static func seal_apply(o, e: Dictionary, s: Dictionary) -> void:
	var g = o.g
	if e.dead or e.chest or e.get("friendly", false) or preload("res://scripts/data.gd").ENEMIES.get(e.get("type", ""), {}).get("seal_immune", false):
		return
	var dur: float = float(s.get("dur", 0.0))
	if e.boss:
		if not s.get("boss", true):
			return
		if float(e.get("seal_imm", -1.0)) > g.t:
			if float(e.get("seal_txt", -1.0)) <= g.t:
				e["seal_txt"] = g.t + 1.5
				o.float_text(e.pos + Vector2(0, -float(e.r) * 2.0 - 30.0), "封印免疫", Color(0.75, 0.7, 0.85), 13)
			return
		dur = minf(dur * float(s.get("boss_mult", 0.3)), float(s.get("boss_max", 1.5)))
		if dur <= 0.0:
			return
		e["seal_imm"] = g.t + dur + float(s.get("boss_immune", 10.0))
	elif e.elite:
		dur *= float(s.get("elite_mult", 0.5))
	if dur <= 0.0:
		return
	var was: bool = float(e.get("seal_t", 0.0)) > g.t
	e["seal_t"] = maxf(float(e.get("seal_t", 0.0)), g.t + dur)
	e["seal_by"] = o.id
	e["seal_look"] = str(s.get("look", ""))   # 标记画法：缺省紫菱形 + 地面圈；cross = 头顶灰叉（拉普兰德）
	sm_st(o).seal[int(e.id)] = e
	if not was and (e.elite or e.boss):
		o.float_text(e.pos + Vector2(0, -float(e.r) * 2.0 - 30.0), "封印", SEAL_COL, 15)


static func sealed(e: Dictionary, t: float) -> bool:
	return float(e.get("seal_t", 0.0)) > t


## verb.mark：本干员对敌人 e 造成了一次伤害（data_operator.deal_damage 之后）
static func mark_hit(o, e: Dictionary) -> void:
	var st: Dictionary = o.sm
	if st.get("mark_busy", false) or e.get("friendly", false) or e.get("chest", false):
		return
	if not st.has("marks"):
		st["marks"] = {}
	var id := int(e.id)
	if e.dead:
		st.marks.erase(id)
		return
	var b: Dictionary = st.mark_b
	var g = o.g
	var m = st.marks.get(id, null)
	if m == null or g.t - float(m.t) > float(b.get("keep", 4.0)):
		m = {"e": e, "n": 0, "t": g.t}
		st.marks[id] = m
	m.n = int(m.n) + 1
	m.t = g.t
	if int(m.n) < int(b.n):
		return
	st.marks.erase(id)
	var at: Vector2 = e.pos
	st["mark_busy"] = true   # on_full 自己的伤害不叠层
	o._exec_list(b.on_full, at)
	st["mark_busy"] = false
	var fl: Array = st.get("mark_fx", []).filter(func(f): return g.t - float(f.t) < 0.4)
	fl.append({"a": o.pos, "b": at, "r": float(e.r), "t": g.t, "id": id})
	st["mark_fx"] = fl


const MARK_COL := Color(0.9, 0.91, 0.94)   # 灰白：层数银圈、收割冲击波与碎片（10-25 用户：红叉丑，冲击波要灰白）
const MARK_RATIO := 0.6   # 静默圈 / 失色区的椭圆压扁比（与 post.gdshader zone_ratio 一致）
const MARK_OPEN := 0.4    # 开场：静默圈从 0 扩到 ring_r 的秒数
const MARK_FADE := 0.35   # 收场淡出秒数

## verb.mark 的画面（技能上层）：开场扩散的静默圈 + 圈内失色（post.gdshader）、层数 = 脚下细银圈逐层加粗、
## 叠满 = 灰白定格 + 灰白冲击波 + 碎片。只读状态与 g.t，不改模拟量、不取随机数
static func _mark_draw(o) -> void:
	var g = o.g
	var cv = o.cv
	var b: Dictionary = o.sm.mark_b
	var on: bool = not b.is_empty()
	var rr: float = float((b if on else o.sm.get("mark_last", _ED)).get("ring_r", 0.0))
	var k_open: float = clampf((g.t - float(o.sm.get("mark_t0", g.t))) / MARK_OPEN, 0.0, 1.0) if on else 1.0
	var k_amt: float = k_open if on else clampf(1.0 - (g.t - float(o.sm.get("mark_t1", -99.0))) / MARK_FADE, 0.0, 1.0)
	var r_now: float = rr * (1.0 - pow(1.0 - k_open, 3.0))
	var post = g.get("post")
	var cfg = g.get_node_or_null("/root/Cfg")   # 积木脚本不直接引用自动加载（契约测试里编译不到）
	var low_q: bool = cfg != null and str(cfg.get("quality")) == "low"
	if post != null and post.get("zone_amt") != null:
		if rr > 0.0 and k_amt > 0.0 and o.pos != Vector2.INF and not low_q:
			var vp = g.get_viewport()
			var xf: Transform2D = vp.get_canvas_transform()
			var vs: Vector2 = vp.get_visible_rect().size
			var sc: float = xf.get_scale().y
			var hc: Vector2 = (xf * (o.pos + Vector2(0, -26))) / vs
			post.zone_amt = 0.8 * k_amt
			post.zone_c = (xf * o.pos) / vs
			post.zone_r = r_now * sc / vs.y
			post.zone_hole = Vector3(hc.x, hc.y, 34.0 * sc / vs.y)
			post.refresh_zone_guards(g)
		else:
			post.zone_amt = 0.0
	if rr > 0.0 and k_amt > 0.0 and o.pos != Vector2.INF:
		var pa: float = (0.22 + 0.06 * sin(g.t * 4.0)) * k_amt
		cv.draw_set_transform(o.pos, 0.0, Vector2(1.0, MARK_RATIO))
		cv.draw_arc(Vector2.ZERO, r_now, 0.0, TAU, 56, Color(MARK_COL.r, MARK_COL.g, MARK_COL.b, pa), 1.5)
		if k_open < 1.0:   # 开场扩散的波前
			cv.draw_arc(Vector2.ZERO, r_now, 0.0, TAU, 56, Color(1, 1, 1, 0.8 * (1.0 - k_open)), 5.0 * (1.0 - k_open) + 1.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if on and o.sm.has("marks"):
		var ls: Array = []
		for id in o.sm.marks:
			var m: Dictionary = o.sm.marks[id]
			var e: Dictionary = m.e
			if e.dead or g.t - float(m.t) > float(b.get("keep", 4.0)):
				continue
			ls.append([o.pos.distance_squared_to(e.pos), int(id), m])
		ls.sort_custom(func(x, y): return x[0] < y[0] if x[0] != y[0] else x[1] < y[1])
		for k in mini(ls.size(), int(b.get("max_show", 8))):
			var m2: Dictionary = ls[k][2]
			var e2: Dictionary = m2.e
			var er: float = float(e2.r)
			var fresh: float = clampf(1.0 - (g.t - float(m2.t)) / 0.12, 0.0, 1.0)   # 新叠一层：0.12 秒亮闪
			cv.draw_set_transform(e2.pos, 0.0, Vector2(1.0, 0.45))
			for L in int(m2.n):
				cv.draw_arc(Vector2.ZERO, er + 4.0 + 4.0 * L, 0.0, TAU, 24, Color(MARK_COL.r, MARK_COL.g, MARK_COL.b, 0.45 + 0.5 * fresh), 1.0 + 0.5 * L + 1.5 * fresh)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for f in o.sm.get("mark_fx", _EA):
		var age: float = g.t - float(f.t)
		if age >= 0.4:
			continue
		var r2: float = float(f.r)
		var cc: Vector2 = f.b + Vector2(0, -r2 * 0.8)
		if age < 0.12:   # 灰白定格
			cv.draw_set_transform(cc, 0.0, Vector2(1.0, 1.2))
			cv.draw_circle(Vector2.ZERO, r2 + 5.0, Color(0.86, 0.87, 0.9, 0.6))
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var kw: float = clampf(age / 0.32, 0.0, 1.0)
		var ez: float = 1.0 - pow(1.0 - kw, 3.0)
		var wr: float = 10.0 + 95.0 * ez   # 冲击波
		cv.draw_set_transform(f.b, 0.0, Vector2(1.0, MARK_RATIO))
		cv.draw_arc(Vector2.ZERO, wr, 0.0, TAU, 40, Color(0.05, 0.05, 0.07, 0.35 * (1.0 - kw)), 9.0 * (1.0 - kw) + 3.0)
		cv.draw_arc(Vector2.ZERO, wr, 0.0, TAU, 40, Color(MARK_COL.r, MARK_COL.g, MARK_COL.b, 1.0 - kw), 6.0 * (1.0 - kw) + 1.0)
		if age < 0.08:
			cv.draw_circle(Vector2.ZERO, 22.0 * (1.0 - age / 0.08) + 6.0, Color(1, 1, 1, 0.7))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for q in 10:   # 碎片：方向按序号均布 + 敌人 id 错开（确定性，不取随机数）
			var a: float = TAU * float(q) / 10.0 + float(int(f.get("id", 0)) % 7) * 0.37
			var dd: float = (14.0 + 70.0 * ez) * (0.7 + 0.3 * float((q * 5 + 3) % 4) / 3.0)
			var pp: Vector2 = cc + Vector2(cos(a), sin(a) * MARK_RATIO) * dd + Vector2(0, 30.0 * kw * kw)
			var sz: float = (4.0 - 2.5 * kw) * (1.0 + float(q % 3) * 0.3)
			var gl: float = 0.1 * float(q % 2)
			cv.draw_rect(Rect2(pp - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(0.78 + gl, 0.79 + gl, 0.82 + gl, 1.0 - kw))


## 技能上层（data_operator._draw_skill_over）：本干员施加的封印标记（头顶旋转的锁环 + 脚下紫环）、主控护盾（泡壳 + 头顶护盾条）
static func sm_draw_over(o) -> void:
	if o.sm.is_empty():
		return
	var g = o.g
	var cv = o.cv
	if o.sm.has("mark_b"):
		_mark_draw(o)
	for id in o.sm.seal:
		var e: Dictionary = o.sm.seal[id]
		if e.dead or not sealed(e, g.t) or str(e.get("seal_by", "")) != o.id:
			continue
		var left: float = float(e.seal_t) - g.t
		var al: float = clampf(left / 0.3, 0.0, 1.0) * 0.9
		var er: float = float(e.r)
		if str(e.get("seal_look", "")) == "cross":   # 灰叉：8×8、2px、#AAAEB2，头顶上方 12px；没有地面圈 / 菱形
			var cp: Vector2 = e.pos + Vector2(0, -er * 2.0 - 12.0)
			var gc := Color(0.667, 0.682, 0.698, al)
			cv.draw_line(cp + Vector2(-4, -4), cp + Vector2(4, 4), Color(0.05, 0.05, 0.06, 0.6 * al), 4.0)
			cv.draw_line(cp + Vector2(-4, 4), cp + Vector2(4, -4), Color(0.05, 0.05, 0.06, 0.6 * al), 4.0)
			cv.draw_line(cp + Vector2(-4, -4), cp + Vector2(4, 4), gc, 2.0)
			cv.draw_line(cp + Vector2(-4, 4), cp + Vector2(4, -4), gc, 2.0)
			continue
		cv.draw_set_transform(e.pos + Vector2(0, er * 0.6), 0.0, Vector2(1.0, 0.45))
		cv.draw_arc(Vector2.ZERO, er + 6.0, 0.0, TAU, 24, Color(SEAL_COL.r, SEAL_COL.g, SEAL_COL.b, 0.55 * al), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var hp: Vector2 = e.pos + Vector2(0, -er * 2.0 - 14.0)
		var rot: float = g.t * 1.6 + float(id)
		var pts := PackedVector2Array()
		for k in 5:
			pts.append(hp + Vector2.from_angle(rot + TAU * k / 4.0) * 7.0)
		cv.draw_polyline(pts, Color(0.05, 0.02, 0.1, 0.7 * al), 4.0)
		cv.draw_polyline(pts, Color(SEAL_COL.r * 1.3, SEAL_COL.g * 1.3, SEAL_COL.b * 1.3, al), 2.0)
		cv.draw_line(hp + Vector2(-3, -3), hp + Vector2(3, 3), Color(1.2, 1.0, 1.4, al), 1.5)
		cv.draw_line(hp + Vector2(-3, 3), hp + Vector2(3, -3), Color(1.2, 1.0, 1.4, al), 1.5)
	var sh: float = float(o.sm.shield)
	if sh > 0.0 and g.ppos != Vector2.INF:
		var k2: float = clampf(sh / maxf(1.0, float(o.sm.shield_max)), 0.0, 1.0)
		var pulse: float = 0.5 + 0.15 * sin(g.t * 5.0)
		cv.draw_set_transform(g.ppos + Vector2(0, -22), 0.0, Vector2(1.0, 1.25))
		cv.draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 40, Color(SHIELD_COL.r, SHIELD_COL.g, SHIELD_COL.b, (0.25 + 0.35 * k2) * pulse), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var bp: Vector2 = g.ppos + Vector2(-20, -100)
		cv.draw_rect(Rect2(bp, Vector2(40, 3)), Color(0.03, 0.05, 0.08, 0.75))
		cv.draw_rect(Rect2(bp, Vector2(40.0 * k2, 3)), Color(SHIELD_COL.r, SHIELD_COL.g, SHIELD_COL.b, 0.95))


# ---------------------------------------------------------------- 护盾 verb.shield / 治疗光环 aura.heal

static func shield_add(o, b: Dictionary) -> void:
	var g = o.g
	var st := sm_st(o)
	var mh: float = g.max_hp
	var add: float = mh * float(b.get("pct", 0.0)) * (o.skill_power() if b.get("power", false) else 1.0)
	var cap: float = mh * float(b.get("cap", b.get("pct", 0.0)))
	st.shield = maxf(float(st.shield), minf(float(st.shield) + add, cap))   # 已有的护盾比上限还多时不削
	st.shield_max = maxf(cap, float(st.shield))
	st.shield_t = maxf(float(st.shield_t), float(b.get("dur", 10.0)))
	st.shield_decay = float(b.get("decay", 0.0))
	if b.has("pop"):   # docs/202：护盾破裂 / 到期时执行的积木列表（pop_cd 秒内至多一次）
		st["pop"] = b.pop
		st["pop_cd"] = float(b.get("pop_cd", 0.0))
	if b.has("fx"):
		fx_play(o, b.fx, g.ppos, 30.0)


## 护盾破裂 / 到期：有 pop 的话下一帧（延迟队列，免得在敌人遍历中途造成伤害）执行；pop_cd 内不重复
static func sm_shield_pop(o) -> void:
	var st: Dictionary = o.sm
	var pop = st.get("pop", null)
	if not (pop is Array) or pop.is_empty() or float(st.get("pop_t", -9.0)) > o.g.t:
		return
	st["pop_t"] = o.g.t + float(st.get("pop_cd", 0.0))
	o.pending.append({"t": 0.0, "do": pop})


## 受击询问（data_operator.dmg_taken_mult 末尾）：m = 其余减伤的乘积，raw = 这一下的伤害；护盾吸收 raw × m 里能吸的部分，返回新的倍率
## （全吸收 = 0，combat 按「这一下作废」处理：不扣血、不掉灯火，给 0.3 秒无敌）
static func shield_mult(o, m: float, raw: float) -> float:
	if o.sm.is_empty() or float(o.sm.shield) <= 0.0:
		return m
	var d: float = raw * m
	if raw <= 0.0 or d <= 0.0:
		return m
	var ab: float = minf(float(o.sm.shield), d)
	o.sm.shield = float(o.sm.shield) - ab
	o.float_text(o.g.ppos + Vector2(18, -92), "护盾 -%d" % int(ab), SHIELD_COL, 13)
	if float(o.sm.shield) <= 0.0:
		sm_shield_pop(o)   # 护盾被打破
	return (d - ab) / raw


## 常驻部分（data_operator._sustain 末尾）：aura.heal 每秒回复（各积木独立计时，没生效的计时清零）
static func sm_sustain(o, act: Array, dt: float) -> void:
	if has_tag(o, "verb.mark"):
		var mk: Dictionary = {}
		for b in act:
			if mk.is_empty() and str(b.get("_tag", "")) == "verb.mark":
				mk = b
		if not mk.is_empty() or o.sm.has("mark_b"):   # 没用过 verb.mark 的干员不建 sm
			var st0 := sm_st(o)
			if mk.is_empty() and not st0.get("mark_b", _ED).is_empty():
				st0["marks"] = {}   # 技能结束：层数全清
				st0["mark_last"] = st0.mark_b
				st0["mark_t1"] = o.g.t   # 画面：收场淡出起点
			elif not mk.is_empty() and st0.get("mark_b", _ED).is_empty():
				st0["mark_t0"] = o.g.t   # 画面：开场扩散起点
			st0["mark_b"] = mk
	var seen := {}
	for b in (act if has_tag(o, "aura.heal") else _EA):   # B6 ④
		if str(b.get("_tag", "")) != "aura.heal":
			continue
		var st := sm_st(o)
		var u: int = int(b.get("_uid", 0))
		seen[u] = true
		if str(b.get("scope", "in_zone")) == "in_zone" and not o.in_zone(o.g.ppos):
			st.heal_acc.erase(u)
			continue
		st.heal_acc[u] = float(st.heal_acc.get(u, 0.0)) + dt
		if st.heal_acc[u] >= 1.0:
			st.heal_acc[u] -= 1.0
			var g = o.g
			if g.hp < g.max_hp:
				o.heal_leader(g.max_hp * float(b.get("pct", 0.0)) * float(o.loc.heal) * (o.skill_power() if b.get("power", false) else 1.0), str(b.get("src", o.display_name())))
	if not o.sm.is_empty() and not o.sm.heal_acc.is_empty():
		for u in o.sm.heal_acc.keys():
			if not seen.has(u):
				o.sm.heal_acc.erase(u)


## Tab / 头像下的状态条：各种召唤物在场数、护盾
static func sm_status_items(o) -> Array:
	var out: Array = []
	if o.sm.is_empty():
		return out
	var cnt := {}
	for s in o.sm.list:
		cnt[s.kind] = int(cnt.get(s.kind, 0)) + 1
	for k in cnt:
		var kd := sm_kind(o, k)
		if not kd.get("status", true):   # 召唤物扩展段：status: false = 不显示在场数（常驻随行的 Mon3tr）
			continue
		out.append(["%s ×%d" % [str(kd.get("name", k)), int(cnt[k])], _sm_col(o, kd)])
	if float(o.sm.shield) > 0.0:
		out.append(["护盾 %d" % int(o.sm.shield), SHIELD_COL])
	return out


# ---------------------------------------------------------------- 召唤 / 封印段的校验

## blocks.summons 段：每种召唤物的定义（docs/61 §15.1）
static func _sm_kinds(blocks: Dictionary, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	var sd = blocks.get("summons", {})
	if not (sd is Dictionary):
		errs.append("blocks.summons 必须是对象（种类名 → 定义）")
		return
	for k in sd:
		var p := "blocks.summons." + str(k)
		var kd = sd[k]
		if not str(k).is_valid_identifier():
			errs.append(p + "：种类名只能是字母 / 数字 / 下划线（不以数字开头）")
		if not (kd is Dictionary):
			errs.append(p + " 必须是对象")
			continue
		for q in kd:
			if not q in SM_KIND_KEYS + MF_KIND_KEYS + E5_KIND_KEYS:
				errs.append("%s.%s：召唤物定义不认识的字段（只能是 %s）" % [p, q, " / ".join(SM_KIND_KEYS + MF_KIND_KEYS + E5_KIND_KEYS)])
		_sm_exprs(kd, p, ctx)
		var inv = kd.get("invuln", false)
		if not (inv is bool):
			errs.append(p + ".invuln 只能是 true / false")
		elif not inv:
			_num(kd, "hp", p, ctx, not kd.has("hp_k"), 1.0, 100000.0)
		elif kd.has("hp") or kd.has("hp_k"):
			errs.append(p + "：invuln（无敌）的召唤物不写 hp / hp_k")
		if kd.has("hp_k"):
			_num(kd, "hp_k", p, ctx, false, 0.1, 50.0)
			if str(kd.get("move", _ED).get("mode", "")) != "escort":
				errs.append(p + ".hp_k：只有随行（escort）召唤物能用（倒下 / 复活 / 治疗分配走随行分支）")
		if kd.has("on_down"):
			_list(kd.on_down, p + ".on_down", "instant", ctx)
		var lv = kd.get("life", null)
		if lv == null:
			errs.append(p + " 缺 life（秒数 / \"skill\" = 召唤它的技能生效期间 / \"permanent\"）")
		elif lv is String and not "$" in lv:
			if not lv in ["skill", "permanent"]:
				errs.append(p + ".life 只能是秒数、\"skill\" 或 \"permanent\"")
		else:
			_num(kd, "life", p, ctx, true, 0.5, 120.0)
		_num(kd, "cap", p, ctx, true, 1.0, float(SM_KIND_CAP))
		_num(kd, "r", p, ctx, false, 4.0, 40.0)
		_num(kd, "decoy_r", p, ctx, false, 20.0, 600.0)
		_num(kd, "hurt_mult", p, ctx, false, 0.0, 5.0)
		if not str(kd.get("enemy_target", "ignore")) in ["ignore", "decoy"]:
			errs.append(p + ".enemy_target 只能是 ignore（缺省：敌人不理召唤物）/ decoy（诱饵：近战杂兵改追它、贴身时它挨打）")
		if kd.has("col"):
			var c = kd.col
			if not (c is Array) or c.size() != 3 or c.any(func(x): return not (x is int or x is float)):
				errs.append(p + ".col 必须是 3 个数字 [r, g, b]")
		var mv = kd.get("move", null)
		if not (mv is Dictionary):
			errs.append(p + ".move 必须是对象（mode / speed / anchor / leash / orbit_r / orbit_speed / target）")
		else:
			for q in mv:
				if not q in SM_MOVE_KEYS + MF_MOVE_KEYS + E5_MOVE_KEYS:
					errs.append("%s.move.%s：不认识的字段（只能是 %s）" % [p, q, " / ".join(SM_MOVE_KEYS + MF_MOVE_KEYS + E5_MOVE_KEYS)])
			_sm_exprs(mv, p + ".move", ctx)
			if not str(mv.get("mode", "")) in SM_MOVES + ["escort"]:
				errs.append("%s.move.mode 只能是 %s" % [p, " / ".join(SM_MOVES + ["escort"])])
			if not str(mv.get("anchor", "leader")) in ["leader", "self"]:
				errs.append(p + ".move.anchor 只能是 leader / self")
			if not str(mv.get("target", "nearest")) in SM_TARGETS:
				errs.append("%s.move.target 只能是 %s" % [p, " / ".join(SM_TARGETS)])
			_num(mv, "speed", p + ".move", ctx, false, 0.0, 1200.0)
			_num(mv, "leash", p + ".move", ctx, false, 40.0, 800.0)
			_num(mv, "orbit_r", p + ".move", ctx, false, 0.0, 400.0)
			_num(mv, "orbit_speed", p + ".move", ctx, false, -6.0, 6.0)
		var a = kd.get("attack", null)
		if a != null:
			if not (a is Dictionary) or not str(a.get("shape", "")) in ["circle", "cone", "line"]:
				errs.append(p + ".attack 必须是一个伤害形状（shape.circle / shape.cone / shape.line）")
			else:
				_block(a, p + ".attack", "attack", ctx)
				_num(a, "every", p + ".attack", ctx, true, 0.1, 10.0)
				_num(a, "range", p + ".attack", ctx, false, 4.0, 600.0)
				if str(a.shape) == "circle" and not str(a.get("center", "self")) in ["self", "target"]:
					errs.append(p + ".attack.center：召唤物的圆形判定只能以自身（self）或目标（target）为心")
		_mf_kind(kd, p, ctx)   # 召唤物扩展段（§15.9）：escort / anim / patch / fx …
		_F()._e5_kind(kd, p, ctx)   # 精英化第 5 批段：zone / move.repick / 非随行召唤物的 anim
		for lk in ["on_spawn", "on_expire"]:
			if kd.has(lk):
				_list(kd[lk], "%s.%s" % [p, lk], "instant", ctx)
				if kd[lk] is Array and kd[lk].any(func(x): return x is Dictionary and str(x.get("verb", "")) == "summon"):
					errs.append("%s.%s：不能再召唤（免得召唤物连环生成）" % [p, lk])
		if kd.has("body"):
			var bd = kd.body
			if not (bd is Dictionary):
				errs.append(p + ".body 必须是对象")
			else:
				for q in bd:
					if not q in SM_BODY_KEYS:
						errs.append("%s.body.%s：不认识的字段（只能是 %s）" % [p, q, " / ".join(SM_BODY_KEYS)])
				var sn = bd.get("strip", "")
				if not (sn is String) or not (sn.begins_with("fx_") or sn.begins_with("proj_") or sn.begins_with("op_") or sn.begins_with("ally_")):
					errs.append(p + ".body.strip 必须是帧条名（fx_* / proj_* / op_* / ally_*）；缺图时画程序体")
				_num(bd, "frames", p + ".body", ctx, false, 1.0, 64.0)
				_num(bd, "fps", p + ".body", ctx, false, 1.0, 60.0)
				_num(bd, "scale", p + ".body", ctx, false, 0.1, 8.0)
				_num(bd, "hover", p + ".body", ctx, false, 0.0, 60.0)
				if bd.has("flip") and not (bd.flip is bool):
					errs.append(p + ".body.flip 只能是 true / false")
				for kk in [["tint", 3, 4], ["anchor", 2, 2]]:
					if bd.has(kk[0]):
						var v = bd[kk[0]]
						if not (v is Array) or v.size() < kk[1] or v.size() > kk[2] or v.any(func(x): return not (x is int or x is float)):
							errs.append("%s.body.%s 必须是 %d%s 个数字的数组" % [p, kk[0], kk[1], "" if kk[1] == kk[2] else "–%d" % kk[2]])


## 对象里一层的 $ 表达式（召唤物定义 / move 不是积木，_block 的 $ 扫描管不到）
static func _sm_exprs(d: Dictionary, p: String, ctx: Dictionary) -> void:
	for k in d:
		if d[k] is String and "$" in d[k]:
			var ev := eval_expr(d[k], ctx.base)
			if not ev[0]:
				ctx.errs.append("%s.%s：%s" % [p, k, ev[2]])


## 本段的积木：校验完返回 true（_block 不再往下走）；不是本段的返回 false
static func _sm_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in SM_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {
		"verb.summon": ["skill", "instant"],
		"verb.shield": ["skill", "instant"],
		"st.seal": ["on_hit", "field"],
		"aura.heal": ["skill", "sustain"],
		"verb.mark": ["skill", "sustain"],
	}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"verb.summon":
			var k := str(b.get("kind", ""))
			var sd = ctx.get("summons", {})
			var kd = sd.get(k, null) if sd is Dictionary else null
			if not (kd is Dictionary):
				errs.append("%s.kind「%s」没在 blocks.summons 里定义" % [p, k])
			_num(b, "n", p, ctx, false, 1.0, float(SM_KIND_CAP))
			_num(b, "spread", p, ctx, false, 0.0, 200.0)
			if not str(b.get("at", "self")) in SM_AT:
				errs.append("%s.at 只能是 %s" % [p, " / ".join(SM_AT)])
			var lv = b.get("life", kd.get("life", 0.0) if kd is Dictionary else 0.0)
			if b.has("life"):
				if lv is String and not "$" in lv:
					if not lv in ["skill", "permanent"]:
						errs.append(p + ".life 只能是秒数、\"skill\" 或 \"permanent\"")
				else:
					_num(b, "life", p, ctx, true, 0.5, 120.0)
			if lv is String and lv == "skill" and kind != "skill":
				errs.append(p + "：life = skill（随技能结束消失）的召唤只能放在技能 do 里")
		"verb.shield":
			_num(b, "pct", p, ctx, true, 0.01, 1.0)
			_num(b, "cap", p, ctx, false, 0.01, 2.0)
			_num(b, "dur", p, ctx, false, 0.5, 60.0)
			_num(b, "decay", p, ctx, false, 0.0, 1.0)
		"st.seal":
			if b.has("look") and not str(b.look) in ["", "cross"]:
				errs.append(p + ".look 只能是 cross（头顶灰叉）")
			_num(b, "dur", p, ctx, true, 0.1, 10.0)
			_num(b, "elite_mult", p, ctx, false, 0.0, 1.0)
			_num(b, "boss_mult", p, ctx, false, 0.0, 1.0)
			_num(b, "boss_max", p, ctx, false, 0.0, 3.0)
			_num(b, "boss_immune", p, ctx, false, 3.0, 60.0)
			if b.has("boss") and not (b.boss is bool):
				errs.append(p + ".boss 只能是 true / false")
		"verb.mark":
			_num(b, "n", p, ctx, true, 2.0, 9.0)
			_num(b, "keep", p, ctx, false, 0.5, 20.0)
			_num(b, "ring_r", p, ctx, false, 0.0, 400.0)
			_num(b, "max_show", p, ctx, false, 1.0, 32.0)
			if not (b.get("on_full", null) is Array) or b.on_full.is_empty():
				errs.append(p + ".on_full 必须是非空的瞬时积木数组（叠满时以该敌人为 target 执行）")
			else:
				_list(b.on_full, p + ".on_full", "instant", ctx)
		"aura.heal":
			_num(b, "pct", p, ctx, true, 0.0, 0.1)
			if not str(b.get("scope", "in_zone")) in ["in_zone", "always"]:
				errs.append(p + ".scope 只能是 in_zone（主控在本干员区域内）/ always")
	return true


# ================================================================ 召唤物扩展段（docs/61 §15.9，10-12：凯尔希 Mon3tr 迁到通用召唤积木；只往后加）
# 给「常驻随行、按状态播帧条、技能期间改攻击」一类召唤物用的通用扩展（第一个用户：凯尔希的 Mon3tr）：
#  trig.on_deploy        招募 / 节点生效时执行一次（召唤物从上场起就在）
#  move.mode = escort    随行：闲时站本干员身前 rest，追锚点 leash 内离锚点最近的敌人、从当前一侧贴到 gap 处；
#                        出手动作期间不走；绕开本干员 / 主控（avoid，滞回）、柱子推出（solid）、离锚点 recall 外瞬回
#  anim                  按状态的帧条 {idle, run, attack}（干员自己 sprites 里的键）；攻击在 attack 帧条的出手帧（fire）才判定
#  patch                 条件成立（如 skill_active:2）时的攻击覆盖：mult（× 技能强度 power）、src（如真伤来源）、speed、
#                        anim / seq（换帧条、起手 + 循环 + 收尾）、tint、sfx；第一条成立的生效
#  verb.summon_mod       常驻：某种召唤物的 dmg / aspd / reach / arc / speed 倍率（按 §5.5 固定顺序依次乘），
#                        then（延迟 delay 秒再追一击 mult）、mirror（同时向身后镜像一击 mult，没打到不画）
#  manual = command      手动普攻 B 类：按攻击键才命令召唤物扑向瞄准方向的目标，松手 manual/m_linger 秒内打完
#  fx（种类 / 攻击上）     §5.6 条目之外的程序条目：pfx / gfx / sprite / sparks / arc / text / banner / pause / sfx；
#                        种类上另有 ghost（残影）/ mist（身后红雾）/ side（身体两侧的常驻爪刃）。散布一律 g.vrng
#  verb.guard            瞬时：限时减伤（同名共用一个计时，重复施加重新计时），dmg_taken_mult 里按积木顺序相乘；look 画护壳
#  verb.cleanse          瞬时：清除主控负面状态（what: nerve = 神经损伤）
#  verb.heal 追加        scale: op（× op_atk × 同伴倍率 × heal_out）、knight（同时治骑士同伴）、on_over（溢出时执行）、text / sfx
#  shape.support         普攻不造成伤害：every 秒一拍、when 条件成立时朝主控起手、出手帧执行 do（凯尔希的治疗）
#  条件追加              node:<custom 节点 id>（已选这个节点）、hurt_any（主控或骑士同伴没满血）、a && b
#  trig.on_skill_start / on_skill_end 追加 at（summon:<种类> / self / leader）：do 里 center: target 落在触发那一刻的这个点，
#                        带 at 的 on_skill_end 在本帧开头结算（召唤物移动之前），二者都可写 delay（进本干员延迟队列）

const MF_TAGS := ["verb.summon_mod", "verb.guard", "verb.cleanse", "trig.on_deploy"]

const MF_KIND_KEYS := ["anim", "patch", "float", "shadow", "fx", "status", "manual"]

const MF_MOVE_KEYS := ["rest", "gap", "avoid", "solid", "recall"]

const MF_PATCH_KEYS := ["cond", "mult", "power", "src", "speed", "anim", "seq", "tint", "sfx", "_doc"]

const MF_MOD_FACTORS := ["dmg", "aspd", "reach", "arc", "speed"]

const MF_FX_KINDS := ["pfx", "gfx", "sprite", "sparks", "arc", "text", "banner", "pause", "sfx", "ghost", "mist", "side"]

const MF_FX_COMMON := ["cond", "if_tex", "at", "max_pts", "off", "n", "every", "jit", "jit_r", "ring", "r_scale", "vel_r", "ang_vel", "along", "side_x", "r_mult",
	"first_only", "face_x", "to", "to_off", "to_jit", "_doc"]

const MF_SPRITE_KEYS := ["fit", "scale_r", "scale", "rot", "second_scale", "second_rot", "swing_rot", "tint", "bottom", "flip_side", "rot_ang"]

const MF_PFX_KINDS := ["ring", "glow", "spark", "shard", "line", "mote", "crescent", "impact", "core", "qshard", "beamray", "crack", "flame", "lava_pillar", "s1link", "h4_cross", "ulp_wave", "ulp_fracture", "ulp_burst", "sk_song"]   # Custom kinds route through hw_draw_pfx.

const MF_GFX_KINDS := ["beam", "rays", "cross"]

const MF_AT := ["center", "self", "leader", "hits", "summon"]

const MF_CLEANSE := ["nerve"]

const MF_GUARD_KEYS := ["verb", "value", "dur", "name", "col", "look", "fx", "cond", "_doc"]

const MF_LOOK_KEYS := ["strip", "frames", "fps", "anchor", "alpha", "off", "fade_in", "blink", "r"]

const MF_FACE_MIN := 0.35   # 同 character.gd FACE_MIN（转向防抖）

const MfBal = preload("res://scripts/core/balance.gd")


## 干员的扩展状态（data_operator.mf）：guards（名字 → {t, v, u, dur, col, look}）、mods（种类 → 倍率表）、deployed（已执行的 on_deploy）
static func mf_st(o) -> Dictionary:
	if o.mf.is_empty():
		o.mf.merge({"guards": {}, "mods": {}, "deployed": {}})
	return o.mf


static func _mf_col(v, def := Color.WHITE) -> Color:
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return def


# ---------------------------------------------------------------- 条件追加（parse_cond / cond_true 转来）

static func mf_parse_cond(s: String, base: Dictionary) -> Dictionary:
	if "&&" in s:
		var out := {"neg": false, "k": "all", "a": "", "op": "", "v": 0.0, "list": []}
		for part in s.split("&&"):
			var c := parse_cond(part.strip_edges(), base)
			if c.has("err"):
				return c
			out.list.append(c)
		return out
	var neg := s.begins_with("!")
	var t := s.substr(1).strip_edges() if neg else s
	if t.begins_with("node:") and t.length() > 5:
		return {"neg": neg, "k": "node", "a": t.substr(5), "op": "", "v": 0.0}
	if t == "hurt_any":
		return {"neg": neg, "k": "hurt_any", "a": "", "op": "", "v": 0.0}
	return {}


## 返回 [是否本段的条件, 值]
static func mf_cond(o, c: Dictionary) -> Array:
	match str(c.k):
		"all":
			for q in c.list:
				if not cond_true(o, q):
					return [true, false]
			return [true, true]
		"node":
			var tk = o.get("taken")
			return [true, tk is Array and str(c.a) in tk]
		"hurt_any":
			var g = o.g
			return [true, g.hp < g.max_hp or (g.knight.alive and g.knight.hp < g.knight.maxhp) or M3.hurt_any(o)]
	return [false, false]


# ---------------------------------------------------------------- 瞬时 / 常驻积木

## 瞬时（data_operator._exec_list 缺省分支）：verb.guard / verb.cleanse
static func mf_exec(o, b: Dictionary, _at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"verb.guard":
			var st := mf_st(o)
			var nm: String = str(b.get("name", "减伤"))
			var gd: Dictionary = st.guards.get(nm, {})
			if gd.is_empty():
				gd = {"u": int(b.get("_uid", 0))}
				st.guards[nm] = gd
				var keys: Array = st.guards.keys()
				keys.sort_custom(func(x, y): return int(st.guards[x].u) < int(st.guards[y].u))   # 相乘顺序固定：按积木顺序
				var sorted := {}
				for k in keys:
					sorted[k] = st.guards[k]
				st.guards = sorted
			gd.t = float(b.get("dur", 3.0))
			gd.dur = float(b.get("dur", 3.0))
			gd.v = float(b.get("value", 0.0))
			gd.col = _mf_col(b.get("col", []), o.col())
			gd.look = b.get("look", {})
			if b.has("fx"):
				fx_play(o, b.fx, o.g.ppos, 30.0)
		"verb.cleanse":
			for w in b.get("what", _EA):
				if str(w) == "nerve":
					o.g.afflict.clear_nerve()


## 常驻（data_operator._sustain 转来）：verb.summon_mod 按本帧生效顺序整理成每种召唤物的倍率表
static func mf_sustain(o, act: Array) -> void:
	var mods := {}
	for b in (act if has_tag(o, "verb.summon_mod") else _EA):   # B6 ④
		if str(b.get("_tag", "")) != "verb.summon_mod":
			continue
		var k: String = str(b.get("kind", ""))
		if not mods.has(k):
			mods[k] = _mf_mod_empty()
		var m: Dictionary = mods[k]
		for f in MF_MOD_FACTORS:
			if b.has(f):
				m[f].append(float(b[f]))
		if b.has("then") and m.then.is_empty():
			m.then = b.then
		if b.has("mirror") and m.mirror.is_empty():
			m.mirror = b.mirror
		if b.has("lunge") and m.lunge.is_empty():   # 精英化段：扑击
			m.lunge = b.lunge
	if not mods.is_empty() or not o.mf.is_empty():
		mf_st(o).mods = mods


static func _mf_mod_empty() -> Dictionary:
	return {"dmg": [], "aspd": [], "reach": [], "arc": [], "speed": [], "then": {}, "mirror": {}, "lunge": {}}


static func mf_mods(o, kind: String) -> Dictionary:
	if o.mf.is_empty():
		return _mf_mod_empty()
	return o.mf.mods.get(kind, _mf_mod_empty())


## 每帧开头（data_operator.update）：限时减伤计时、trig.on_deploy、带 at 的 trig.on_skill_end（prev = 上一帧的技能剩余秒数）
static func mf_tick(o, dt: float, prev: Array) -> void:
	if not o.mf.is_empty() and not o.mf.guards.is_empty():
		for nm in o.mf.guards:
			var gd: Dictionary = o.mf.guards[nm]
			gd.t = maxf(0.0, float(gd.t) - dt)
	if o.B.get("_mf_deploy", false):
		var st := mf_st(o)
		for t in o._trigs():
			if str(t.get("_tag", "")) == "trig.on_deploy" and not st.deployed.has(int(t._uid)) and o.pos != Vector2.INF and cond_true(o, t.get("cond", _ED)):
				st.deployed[int(t._uid)] = true
				o._exec_list(t.get("do", []))
	for i in 3:
		if prev[i] > 0.0 and o.s_t[i] <= 0.0 and not o.B.get("skills", [{}, {}, {}])[i].has("attack_phases") and not o.SkillLifecycle.owns(o, i):
			for t in o._trigs():
				if str(t.get("_tag", "")) == "trig.on_skill_end" and t.has("at") and int(t.get("skill", -1)) == i and cond_true(o, t.get("cond", _ED)):
					mf_fire_at(o, t, mf_at_point(o, str(t.at)))


## 带 at 的技能触发：delay > 0 进本干员延迟队列（带点），否则立即执行（do 里 center: target = 这个点）
static func mf_fire_at(o, t: Dictionary, p: Vector2) -> void:
	var dl: float = float(t.get("delay", 0.0))
	if dl > 0.0:
		o.pending.append({"t": dl, "do": t.get("do", []), "at": p})
	else:
		o._exec_list(t.get("do", []), p)


## summon:<种类> = 这种召唤物里最早的一个的位置（没有时退回本干员）；self / leader
static func mf_at_point(o, at: String) -> Vector2:
	if at.begins_with("summon"):
		var k: String = at.substr(7) if at.length() > 7 else ""
		if not o.sm.is_empty():
			for s in o.sm.list:
				if k == "" or str(s.kind) == k:
					return s.pos
		return o.pos
	if at == "leader":
		return o.g.ppos
	return o.pos


## 技能起手朝向（blocks.skills[i].aim）：summon:<种类> / leader；没写返回 INF（不转身）
static func mf_skill_aim(o, i: int) -> Vector2:
	var sk: Array = o.B.get("skills", [])
	if i < 0 or i >= sk.size() or not sk[i].has("aim"):
		return Vector2.INF
	var a: String = str(sk[i].aim)
	if a == "los":   # 手写迁移段：普攻射程（attack.range）+ aim_pad（× op_range）内视线优先的最近敌人
		var ra: float = (float(o.B.get("attack", _ED).get("range", 300.0)) + float(sk[i].get("aim_pad", 0.0))) * o.stat(&"op_range")
		var tl: Array = o.los_targets(1, ra, o.pos)
		return tl[0].pos if not tl.is_empty() else Vector2.INF
	if a == "tether":   # 手写迁移段：这个技能的 verb.tether 选的落点
		for tb in sk[i].get("do", _EA):
			if str(tb.get("_tag", "")) == "verb.tether":
				return _F().hw_tether_target(o, tb)
		return Vector2.INF
	if a == "range":   # 手写迁移段：攻击距离（逻各斯段 hw_range）内最近的敌人
		var tr: Array = o.nearest_enemies(1, _F().hw_range(o), o.pos)
		return tr[0].pos if not tr.is_empty() else Vector2.INF
	if a == "elite" or a == "cluster":   # 手写迁移段第 4 批：凋零处刑（精英 / Boss 优先）/ 饱和炮击（离队长最近、相仿挑最密）
		return _F().h4_skill_aim(o, i, a)
	if a == "nearest":   # 手写迁移段：aim_r（世界像素）内最近的敌人，没有 = 不转身
		var ts: Array = o.nearest_enemies(1, float(sk[i].get("aim_r", 200.0)), o.pos)
		return ts[0].pos if not ts.is_empty() else Vector2.INF
	if a.begins_with("summon") and (o.sm.is_empty() or o.sm.list.is_empty()):
		return o.g.ppos
	return mf_at_point(o, a)


## 受击询问（data_operator.dmg_taken_mult）：m × Π(1 - 各生效减伤)，按积木顺序
static func mf_guard_mult(o, m: float) -> float:
	if o.mf.is_empty():
		return m
	for nm in o.mf.guards:
		var gd: Dictionary = o.mf.guards[nm]
		if float(gd.t) > 0.0:
			m *= 1.0 - float(gd.v)
	return m


## 状态条：技能 status（生效中）+ 生效的减伤
static func mf_status_items(o) -> Array:
	var out: Array = []
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		if sk[i].has("status") and o.skill_on(i) and not "%d" in str(sk[i].status):   # 带 %d 的（次数型剩余发数）由手写迁移段 hw_status_items 画
			out.append([str(sk[i].status), _mf_col(sk[i].get("status_col", []), o.col())])
	if not o.mf.is_empty():
		for nm in o.mf.guards:
			if float(o.mf.guards[nm].t) > 0.0:
				out.append([str(nm), o.mf.guards[nm].col])
	return out


## 减伤护壳（verb.guard.look）：主控周身。strip（art.gd 贴图，frames / fps / anchor）缺图时画程序六边形；
## 刚罩上 fade_in 秒淡入，最后 blink 秒闪烁淡出
static func mf_draw_guards(o) -> void:
	if o.mf.is_empty() or o.g.ppos == Vector2.INF:
		return
	var g = o.g
	for nm in o.mf.guards:
		var gd: Dictionary = o.mf.guards[nm]
		var lk: Dictionary = gd.get("look", {})
		var t: float = float(gd.t)
		if t <= 0.0 or lk.is_empty():
			continue
		var bl: float = float(lk.get("blink", 0.5))
		var al: float = 1.0 if t > bl else (0.35 + 0.65 * absf(sin(t * 18.0)))
		var c: Vector2 = g.ppos + Vector2(0, -22)
		var ov = lk.get("off", [])
		if ov is Array and ov.size() == 2:
			c = g.ppos + Vector2(float(ov[0]), float(ov[1]))
		var stx: Texture2D = ArtS.tex(str(lk.get("strip", ""))) if lk.has("strip") else null
		if stx != null:
			var fr: int = maxi(1, int(lk.get("frames", 1)))
			var fin: float = clampf((float(gd.dur) - t) / maxf(0.01, float(lk.get("fade_in", 0.2))), 0.0, 1.0)
			var av = lk.get("anchor", [])
			var an: Vector2 = Vector2(float(av[0]), float(av[1])) if av is Array and av.size() == 2 else Vector2.ZERO
			o._strip(stx, fr, int(g.t * float(lk.get("fps", 6))) % fr, c, g.PX, an, false, Color(1, 1, 1, float(lk.get("alpha", 0.5)) * al * fin))
			continue
		var cc: Color = gd.col
		var R: float = float(lk.get("r", 34.0)) + 1.5 * sin(g.t * 5.0)
		var hexp := PackedVector2Array()
		for i in 7:
			var an2: float = g.t * 0.6 + i * TAU / 6.0
			hexp.append(c + Vector2(cos(an2) * R, sin(an2) * R * 1.12))
		o.cv.draw_colored_polygon(hexp.slice(0, 6), Color(cc.r * 0.7, cc.g * 1.3, cc.b * 0.9, 0.13 * al))
		o.cv.draw_polyline(hexp, Color(minf(cc.r * 1.6, 2.0), 2.0, minf(cc.b * 1.6, 2.0), 0.7 * al), 2.0)
		for i in 3:
			o.cv.draw_line(hexp[i], hexp[i + 3], Color(cc.r * 1.2, cc.g * 1.7, cc.b * 1.3, 0.18 * al), 1.0)


# ---------------------------------------------------------------- 随行召唤物（move.mode = escort）

## 闲时站位：本干员脚底 + rest（x 乘本干员朝向）
static func mf_rest(o, mv: Dictionary) -> Vector2:
	var rv = mv.get("rest", [44, 18])
	var r := Vector2(float(rv[0]), float(rv[1])) if rv is Array and rv.size() == 2 else Vector2(44, 18)
	return o.pos + r * Vector2(o.face, 1.0)


## 攻击距离：r × op_range × 各 reach 倍率（依次乘）
static func mf_reach(o, a: Dictionary, mods: Dictionary) -> float:
	var r: float = float(a.get("r", 30.0)) * o.stat(&"op_range") * VisGrowth.summon_reach(o.g)
	for f in mods.reach:
		r *= f
	return r


## 出手伤害：base[atk_key] × _dmg_bonus × 各 dmg 倍率 [× patch.mult（× 技能强度）]
static func mf_dmg(o, a: Dictionary, mods: Dictionary, pt: Dictionary) -> float:
	var d: float = o.base(str(a.get("atk_key", "atk")), 0.0) * o._dmg_bonus()
	for f in mods.dmg:
		d *= f
	if pt.has("mult"):
		d *= float(pt.mult) * (o.skill_power() if pt.get("power", false) else 1.0)
	return d


## 转向防抖：距上次翻身至少 FACE_MIN 秒（同干员本体）
static func _mf_face(o, s: Dictionary, want: float) -> void:
	if want == 0.0 or want == float(s.face) or o.g.t - float(s.get("flip_t", -99.0)) < MF_FACE_MIN:
		return
	s.face = want
	s.flip_t = o.g.t


static func _mf_set_anim(s: Dictionary, k: String) -> void:
	if str(s.ak) != k:
		s.ak = k
		s.at = 0.0


## 回位 / 追击路径绕开 avoid 里的人（self = 本干员、leader = 主控）：直线会从人身上穿过时，先走到那人脚下前方 56 的绕行点；
## 滞回：进了绕行就走到绕行点（16 内）或 1.2 秒后才退出，退出后 0.4 秒内不再进入（docs/45 §5 的 Mon3tr 走位）
static func _mf_route(o, s: Dictionary, mv: Dictionary, want: Vector2) -> Vector2:
	var av = mv.get("avoid", [])
	if not (av is Array) or av.is_empty():
		return want
	var g = o.g
	if s.via != Vector2.INF:
		if s.pos.distance_to(s.via) > 16.0 and g.t - float(s.via_t) < 1.2:
			return s.via
		s.via = Vector2.INF
		s.via_off = g.t
	if g.t - float(s.via_off) < 0.4:
		return want
	var cs: Array = []
	for w in av:
		cs.append(o.pos if str(w) == "self" else g.ppos)
	for c in cs:
		if c == Vector2.INF or s.pos.distance_to(c) < 12.0 or want.distance_to(c) < 12.0:
			continue
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(c, s.pos, want)
		if q.distance_to(c) < 40.0 and absf(s.pos.y - c.y) < 50.0:
			var via: Vector2 = c + Vector2(0, 56)
			if mv.has("solid") and g.tex.get("prop_pillar") != null:
				via = g.map.push_out(via, float(mv.solid))
			if s.pos.distance_to(via) > 32.0:
				s.via = via
				s.via_t = g.t
				return via
	return want


## 当前生效的 patch（第一条 cond 成立的；没有 = {}）。换 patch 时记下旧 patch 的 seq 收尾秒数
static func _mf_patch_tick(o, s: Dictionary, kd: Dictionary, dt: float) -> Dictionary:
	var pl: Array = kd.get("patch", [])
	var idx := -1
	for i in pl.size():
		if cond_true(o, pl[i].get("cond", _ED)):
			idx = i
			break
	if idx != int(s.pidx):
		SummonVisual.cancel(s)
		var old: int = int(s.pidx)
		if old >= 0 and old < pl.size() and pl[old].has("seq"):
			s.pout = float(pl[old].seq.get("out", 0.0))
			s.pold = old
		s.pidx = idx
		s.pt = 0.0
	s.pt = float(s.pt) + dt
	s.pout = maxf(0.0, float(s.pout) - dt)
	s.pcur = pl[idx] if idx >= 0 else {}
	return s.pcur


## 种类 fx 的定时部分：带 every 的条目在召唤物处播；ghost 每 every 秒记一次残影（条件不成立时清掉）
static func _mf_fx_tick(o, s: Dictionary, kd: Dictionary, dt: float) -> void:
	var fl: Array = kd.get("fx", [])
	if fl.is_empty():
		return
	var gh := false
	for i in fl.size():
		var f: Dictionary = fl[i]
		if f.has("ghost"):
			if not fx_on(o, f):
				continue
			gh = true
			if s.ghost.is_empty() or float(s.ghost.t) <= 0.0:
				s.ghost = {"pos": s.pos, "face": s.face, "ak": s.ak, "at": s.at, "t": float(f.ghost.get("every", 0.12)), "frame": _mf_frame(o, s, kd, str(s.ak), float(s.at))}
			else:
				s.ghost.t = float(s.ghost.t) - dt
			continue
		var ev: float = float(f.get("every", 0.0))
		if ev <= 0.0:
			continue
		var tm: float = float(s.fxt.get(i, 0.0)) - dt
		if tm <= 0.0:
			tm = ev
			if fx_on(o, f):
				if mf_is(f):
					mf_fx_spawn(o, f, {"c": s.pos, "r": float(kd.get("r", 10.0)), "s": s})
				else:
					fx_spawn(o, f, s.pos, float(kd.get("r", 10.0)), [], 0.0)
		s.fxt[i] = tm
	if not gh:
		s.ghost = {}


## 一步（sm_tick 转来，代替 _sm_step）：顺序同原 Mon3tr——瞬回 → patch / 画面计时 → 选目标 → 移动 → 冷却 → 追击队列 → 出手动作 / 起手 → 动画状态
static func mf_step(o, s: Dictionary, kd: Dictionary, dt: float) -> void:
	var g = o.g
	var mv: Dictionary = kd.get("move", {})
	var a: Dictionary = kd.get("attack", {})
	var mods: Dictionary = mf_mods(o, str(s.kind))
	var rest := mf_rest(o, mv)
	if s.pos == Vector2.INF or s.pos.distance_to(g.ppos) > float(mv.get("recall", SM_FAR)):
		s.pos = rest
	var pt := _mf_patch_tick(o, s, kd, dt)
	_mf_fx_tick(o, s, kd, dt)
	if s.has("dash"):   # 精英化段：扑击 / 回防跃回中（位移、落地结算、帧条都在 el_dash_step）
		SummonVisual.cancel(s)
		_F().el_dash_step(o, s, kd, mods, dt)
		return
	var leash: float = float(mv.get("leash", 240.0))
	var anc: Vector2 = _sm_anchor(o, mv)
	var tg = s.tgt
	if str(kd.get("manual", "")) == "command" and o.manual_attack():
		# 手动普攻 B 类（契约 v2.5）：按攻击键命令召唤物扑向瞄准方向的目标；按下时换目标，松手后 manual/m_linger 秒内打完手上这个
		if g.doctor.attack_want():
			s.cmd_t = MfBal.v("manual/m_linger", 1.2)
			if g.doctor.atk_edge or tg == null or tg.dead or tg.pos.distance_to(anc) > leash + 40.0:
				var tsm: Array = o.aim_targets(1, leash, anc)
				if not tsm.is_empty() and int(tsm[0].get("id", 0)) >= 0:   # 伪目标（指向上没敌人）不命令
					tg = tsm[0]
					g.doctor.atk_buf = 0.0
		else:
			s.cmd_t = maxf(0.0, float(s.cmd_t) - dt)
		if float(s.cmd_t) <= 0.0 or (tg != null and (tg.dead or tg.pos.distance_to(anc) > leash + 40.0)):
			tg = null
		s.tgt = tg
	elif tg == null or tg.dead or tg.pos.distance_to(anc) > leash + 40.0:
		var ts: Array = o.nearest_enemies(1, leash, anc)
		tg = ts[0] if not ts.is_empty() else null
		s.tgt = tg
	if tg != null and float(s.act) <= 0.0 and not mods.get("lunge", {}).is_empty() and _F().el_lunge_try(o, s, kd, tg, mods.lunge):   # 精英化段：扑击
		SummonVisual.cancel(s)
		return
	var want: Vector2 = rest
	if tg != null:
		var off: Vector2 = s.pos - tg.pos
		want = tg.pos + (off.normalized() if off.length() > 1.0 else Vector2(-float(s.face), 0)) * (float(tg.r) + float(mv.get("gap", 26.0)))
	var prev: Vector2 = s.pos
	if float(s.act) <= 0.0:
		var spd: float = float(mv.get("speed", 240.0))
		if pt.has("speed"):
			spd *= float(pt.speed)
		for f in mods.speed:
			spd *= f
		var d: Vector2 = _mf_route(o, s, mv, want) - s.pos
		s.pos += d.normalized() * minf(d.length(), spd * dt)
		if mv.has("solid") and g.tex.get("prop_pillar") != null:
			s.pos = g.map.push_out(s.pos, float(mv.solid))
	var vel: Vector2 = (s.pos - prev) / maxf(dt, 0.0001)
	s.mv = lerpf(float(s.mv), vel.length(), clampf(dt * 10.0, 0.0, 1.0))
	if absf(vel.x) > 20.0 and float(s.act) <= 0.0:
		_mf_face(o, s, signf(vel.x))
	var k: float = dt
	for f in mods.aspd:
		k *= f
	s.cd = float(s.cd) - k
	if not s.pend.is_empty():
		for pc in s.pend:
			pc.t -= dt
			if pc.t <= 0.0:
				_mf_claw(o, s, kd, float(pc.mult), true)
		s.pend = s.pend.filter(func(pc): return pc.t > 0.0)
	if float(s.act) > 0.0:
		s.act = float(s.act) - dt
		if float(s.fire) >= 0.0:
			s.fire = float(s.fire) - dt
			if float(s.fire) < 0.0:
				s.fire = -1.0
				_mf_strike(o, s, kd)
	elif tg != null and not a.is_empty() and float(s.cd) <= 0.0 and s.pos.distance_to(tg.pos) < float(tg.r) + mf_reach(o, a, mods):
		s.cd = float(a.get("every", 1.0)) / o.stat(&"op_aspd")
		if absf(tg.pos.x - s.pos.x) > 2.0:
			_mf_face(o, s, signf(tg.pos.x - s.pos.x))
		var spec: Dictionary = o.sprite_spec(str(kd.get("anim", _ED).get("attack", "")))
		var fps: float = float(spec.get("fps", 14))
		s.act = float(spec.get("frames", 4)) / fps
		s.fire = (float(spec.get("fire", 2)) + 0.5) / fps
		var visual_key: String = str(s.pcur.get("anim", {}).get("attack", kd.get("anim", _ED).get("attack", "")))
		SummonVisual.start(s, o.sprite_spec(visual_key).get("visual", {}), g.t, float(s.fire))
		_mf_set_anim(s, "attack")
	_mf_set_anim(s, "attack" if float(s.act) > 0.0 else ("run" if float(s.mv) > 30.0 else "idle"))
	s.at = float(s.at) + dt


static func _mf_strike(o, s: Dictionary, kd: Dictionary) -> void:
	SummonVisual.hit(s, o.g.t)
	s.swing = -float(s.swing)
	_mf_claw(o, s, kd, 1.0, false)
	var th: Dictionary = mf_mods(o, str(s.kind)).then
	if not th.is_empty():
		s.pend.append({"t": float(th.get("delay", 0.1)), "mult": float(th.get("mult", 0.5))})


## 一击：朝 dir（face = 召唤物面向；target = 朝目标）挥出锥形；mirror 时同时向身后镜像一击（没打到不画）。second = then 的追击
static func _mf_claw(o, s: Dictionary, kd: Dictionary, mult: float, second: bool) -> void:
	var a: Dictionary = kd.get("attack", {})
	var mods: Dictionary = mf_mods(o, str(s.kind))
	var pt: Dictionary = s.pcur
	var fwd: float = 0.0 if float(s.face) >= 0.0 else PI
	if str(a.get("dir", "face")) == "target" and s.tgt != null and not s.tgt.dead:
		fwd = (s.tgt.pos - s.pos).angle()
	var ov = a.get("origin", [])
	var org: Vector2 = s.pos + (Vector2(float(ov[0]), float(ov[1])) if ov is Array and ov.size() == 2 else Vector2.ZERO)
	var fv = a.get("fx_origin", ov)
	var fo: Vector2 = s.pos + (Vector2(float(fv[0]), float(fv[1])) if fv is Array and fv.size() == 2 else Vector2.ZERO)
	var half: float = float(a.half) if a.has("half") else deg_to_rad(float(a.get("half_deg", 45.0)))
	for f in mods.arc:
		half *= f
	var mi: Dictionary = mods.mirror
	var dirs: Array = [fwd, fwd + PI] if not mi.is_empty() else [fwd]
	var src: String = str(pt.get("src", a.get("src", "")))
	var tags: Array = a.get("tags", []).duplicate()
	if not "summon" in tags:
		tags.append("summon")
	var any := false
	for i in dirs.size():
		var ang: float = dirs[i]
		var sd: float = 1.0 if cos(ang) >= 0.0 else -1.0
		var reach := mf_reach(o, a, mods)
		var dmg: float = mf_dmg(o, a, mods, pt) * mult * (1.0 if i == 0 else float(mi.get("mult", 1.0)))
		var hits: Array = o.melee_hit(src, org, ang, half, reach + float(a.get("pad", 0.0)), dmg, float(a.get("kb", 0.0)), float(a.get("stun", 0.0)), tags, int(a.get("max_n", 0)))
		any = any or not hits.is_empty()
		for stt in a.get("on_hit", _EA):
			for e in hits:
				apply_status(o, e, stt)
		if not hits.is_empty() and not o.taken.is_empty() and "wide_arc" in o.taken and str(o.id) == "kaltsit":
			sm_debride(o, hits)   # docs/202 清创：爪击累积
		if i > 0 and hits.is_empty():
			continue   # 身后一击没打到时不画（刀光会正好盖在本干员和主控身上，docs/45 #6）
		if a.has("fx"):
			for f in a.fx:
				if f is Dictionary and fx_on(o, f) and not (second and f.get("first_only", false)):
					if mf_is(f):
						mf_fx_spawn(o, f, {"c": fo, "r": reach, "hits": hits, "ang": ang, "sd": sd, "reach": reach, "half": half, "second": second, "swing": float(s.swing), "s": s})
					else:
						fx_spawn(o, f, fo, reach, hits, ang)
	if any:
		var sf: Dictionary = a.get("sfx", {})
		var ps: Dictionary = pt.get("sfx", {})
		if not sf.is_empty():
			var th: Dictionary = mods.then
			_mf_sfx(o, str(sf.get("kind", "atk")), float(ps.get("db", sf.get("db", 0.0))),
				float(ps.get("pitch", sf.get("pitch", 1.0))) * (float(th.get("pitch", 1.0)) if second else 1.0))


static func _mf_sfx(o, kind: String, db: float, pitch: float) -> void:
	var g = o.g
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g != null and g.is_inside_tree() else null
	if sfx != null:
		sfx.op(o.id, kind, db, pitch)


## 悬浮高度（世界像素，负 = 往上）：float {h, amp, hz}：-h - amp × sin(g.t × hz + x × 0.01)
static func _mf_hover(o, s: Dictionary, kd: Dictionary) -> float:
	var fl: Dictionary = kd.get("float", {})
	if fl.is_empty():
		return 0.0
	return -float(fl.get("h", 0.0)) - float(fl.get("amp", 0.0)) * sin(o.g.t * float(fl.get("hz", 2.6)) + s.pos.x * 0.01)


## 这一帧的帧条：[贴图, 帧号, 帧数, 脚底键]；patch 的 seq（起手 intro 帧、loop 段循环、收尾 out 秒停在末帧）代替 idle / run，攻击用 patch.anim.attack
static func _mf_frame(o, s: Dictionary, kd: Dictionary, ak: String, at: float) -> Array:
	var an: Dictionary = kd.get("anim", {})
	var pl: Array = kd.get("patch", [])
	var pt: Dictionary = s.pcur
	var sq: Dictionary = {}
	var live := false
	if pt.has("seq"):
		sq = pt.seq
		live = true
	elif float(s.pout) > 0.0 and int(s.get("pold", -1)) >= 0 and int(s.pold) < pl.size():
		sq = pl[int(s.pold)].get("seq", {})
	if not sq.is_empty() and not ak in ["attack", "lunge", "leap"]:   # lunge / leap：精英化段（扑击 / 跃回）照播自己的帧条
		var key: String = str(sq.get("strip", ""))
		if o.sprite_spec(key).has("visual"):
			var native := mf_visual_frame(o, s, key, float(s.pt))
			if not native.is_empty():
				return native
		var tx: Texture2D = o.anim_tex(key)
		if tx != null:
			var n: int = o.anim_hframes(tx, key)
			var fps: float = float(o.sprite_spec(key).get("fps", 12))
			var fr: int
			if not live:
				fr = n - 1
			else:
				var el: float = float(s.pt)
				var intro: float = float(sq.get("intro", 0)) / fps
				var lp = sq.get("loop", [0, n - 1])
				var l0: int = int(lp[0])
				var ln: int = maxi(1, int(lp[1]) - l0 + 1)
				fr = int(el * fps) if el < intro else l0 + int((el - intro) * fps) % ln
			return [tx, clampi(fr, 0, n - 1), n, key]
	var pa: Dictionary = pt.get("anim", {})
	var visual_key: String = str(pa.get(ak, an.get(ak, an.get("idle", ""))))
	if not ak in ["lunge", "leap"] and (not pa.has(ak) or o.sprite_spec(visual_key).has("visual")):
		var native := mf_visual_frame(o, s, visual_key, at, ak != "attack")
		if not native.is_empty():
			return native
	var base_key: String = str(an.get(ak, an.get("idle", "")))
	var dash: bool = ak in ["lunge", "leap"]
	if dash and o.anim_tex(base_key) == null:   # 精英化段：扑击 / 跃回帧条缺图时用 run 代替（位移与残影照旧）
		base_key = str(an.get("run", an.get("idle", "")))
		dash = false
	var tx2: Texture2D = o.anim_tex(str(pa.get(ak, base_key)))
	if tx2 == null:
		tx2 = o.anim_tex(base_key)
	if tx2 == null:
		return []
	var n2: int = o.anim_hframes(tx2, base_key)
	var fr2: int
	if ak == "attack" or dash:
		fr2 = clampi(int(at * float(o.sprite_spec(base_key).get("fps", 14))), 0, n2 - 1)
	else:
		fr2 = int(at * float(o.sprite_spec(base_key).get("fps", 4))) % n2
	return [tx2, fr2, n2, base_key]


## Opt-in native body; attack recovery is independent of the controller's act/ak.
static func mf_visual_frame(o, s: Dictionary, key: String, elapsed: float, loop: bool = true) -> Array:
	var meta: Dictionary = o.sprite_spec(key).get("visual", {})
	if s.has("visual"):
		var source_time: float = SummonVisual.time(s, o.g.t)
		var active: Dictionary = s.visual.meta
		if source_time < float(active.duration):
			meta = active
			elapsed = source_time
			loop = false
		else:
			SummonVisual.cancel(s)
	if meta.is_empty():
		return []
	var native_key: String = str(meta.anim)
	var tx: Texture2D = o.anim_tex(native_key)
	if tx == null:
		return []
	return [tx, SummonVisual.frame(meta, elapsed, loop), o.anim_hframes(tx, native_key), native_key]


## 画一个随行召唤物（sm_draw 转来）：残影 → 身后红雾 → 本体（按状态帧条、悬浮起伏、patch 染色）→ 两侧爪刃
static func mf_draw(o, s: Dictionary, kd: Dictionary) -> bool:
	var fr := _mf_frame(o, s, kd, str(s.ak), float(s.at))
	if fr.is_empty():
		return false
	var g = o.g
	var hov := _mf_hover(o, s, kd)
	if s.has("m3") and M3.is_down(s):   # 倒地：灰色躺倒剪影 + 复活读秒弧（不画影子以外的装饰）
		M3.draw_down(o, s, kd, fr, 0.0)
		return true
	if s.has("dash"):   # 精英化段：跃回的弧线高度 + 扑击 / 跃回的绿色残影
		hov -= float(s.dash.get("h_now", 0.0))
		_F().el_draw_afterimages(o, s, kd, fr, hov)
	var fl: Array = kd.get("fx", [])
	for f in fl:
		if not (f is Dictionary) or not fx_on(o, f):
			continue
		if f.has("ghost") and not s.ghost.is_empty() and s.ghost.pos.distance_to(s.pos) > 3.0:
			var gf: Array = s.ghost.get("frame", [])
			if not gf.is_empty():
				o.draw_sprite_at(s.ghost.pos + Vector2(0, hov), (float(s.ghost.face) < 0.0) != o.sprite_mirror(str(gf[3])), _mf_col(f.ghost.get("tint", []), Color(1, 1, 1, 0.35)), gf[1], gf[0], gf[2], o.foot_off(gf[0], gf[3]))
		elif f.has("mist"):
			var m: Dictionary = f.mist
			var mc: Color = _mf_col(m.get("col", []), Color(0.85, 0.025, 0.02, 0.12))
			for q in int(m.get("n", 3)):
				var ph: float = g.t * float(m.get("hz", 1.7)) + q * 1.3
				var off := Vector2(cos(ph) * float(m.get("dx", 16.0)), sin(ph * 1.3) * float(m.get("dy", 10.0)) + hov + float(m.get("y", -50.0)))
				o.cv.draw_circle(s.pos + off, float(m.get("r", 14.0)) + float(m.get("rv", 5.0)) * sin(ph * 2.0), mc)
	var col := Color.WHITE
	if float(s.pout) <= 0.0 and s.pcur.has("tint"):
		col = _mf_col(s.pcur.tint)
	o.draw_sprite_at(s.pos + Vector2(0, hov), (float(s.face) < 0.0) != o.sprite_mirror(str(fr[3])), col, fr[1], fr[0], fr[2], o.foot_off(fr[0], fr[3]), VisGrowth.summon_scale(g))
	if s.has("m3"):
		s["draw_top"] = [fr[0], fr[2], o.foot_off(fr[0], fr[3]), VisGrowth.summon_scale(g), hov]   # 头顶血条找头顶（hud_allyhp._m3_head，10-31）
	for f in fl:
		if f is Dictionary and f.has("side") and fx_on(o, f):
			_mf_side(o, s, f.side, hov)
	if s.has("m3"):
		M3.draw_bar(o, s, kd, hov)
	return true


## 身体两侧对称的常驻装饰（爪刃）：strip（art.gd 贴图，frames / fps / anchor，朝右一侧水平镜像）或程序双层弧（col）；j = 第几组（往外 dxj、往下 yj）
static func _mf_side(o, s: Dictionary, sd: Dictionary, hov: float) -> void:
	var g = o.g
	var j: int = int(sd.get("j", 0))
	var body: Vector2 = s.pos + Vector2(0, hov + float(sd.get("body_y", -26.0)))
	var sides: Array = [float(s.face), -float(s.face)]
	var tx: Texture2D = ArtS.tex(str(sd.strip)) if sd.has("strip") else null
	if tx != null:
		var frames: int = maxi(1, int(sd.get("frames", 1)))
		var bf: int = int(g.t * float(sd.get("fps", 4))) % frames
		var av = sd.get("anchor", [])
		var anc: Vector2 = Vector2(float(av[0]), float(av[1])) if av is Array and av.size() == 2 else Vector2.ZERO
		for q in sides:
			var bob: float = sin(g.t * 3.0 + j * 1.7 + q) * float(sd.get("bob", 2.5))
			var bp: Vector2 = body + Vector2(q * (float(sd.get("dx", 33.0)) + float(sd.get("dxj", 5.0)) * j), float(sd.get("y", -10.0)) + float(sd.get("yj", 15.0)) * j + bob)
			o._strip(tx, frames, (bf + j) % frames, bp, g.PX, anc, q > 0.0, Color.WHITE)
		return
	if sd.has("strip") and not sd.has("col"):
		return
	var c: Color = _mf_col(sd.get("col", []), o.col())
	for q in sides:
		var base_a: float = 0.0 if q >= 0.0 else PI
		var sway: float = sin(g.t * 3.0 + j * 1.7 + q) * 0.18
		var cp: Vector2 = body + Vector2(q * (float(sd.get("arc_dx", 27.0)) + float(sd.get("dxj", 5.0)) * j), float(sd.get("y", -10.0)) + float(sd.get("yj", 15.0)) * j)
		var a0: float = base_a - 0.95 + sway
		var a1: float = base_a + 0.95 + sway
		o.cv.draw_arc(cp, 15.0, a0, a1, 12, Color(c.r, c.g, c.b, 0.22), 6.0)
		o.cv.draw_arc(cp, 15.0, a0, a1, 12, Color(c.r * 1.7, c.g * 1.7, c.b * 1.5, 0.85), 2.0)


## 影子：shadow = 影子贴图倍率（悬浮时随起伏缩放 ±10%）；返回 false = 没写，走程序椭圆
static func mf_shadow(o, s: Dictionary, kd: Dictionary) -> bool:
	if not kd.has("shadow"):
		return false
	var fl: Dictionary = kd.get("float", {})
	var k: float = float(kd.shadow)
	if not fl.is_empty():
		k *= 1.0 - 0.1 * sin(o.g.t * float(fl.get("hz", 2.6)) + s.pos.x * 0.01)
	o.draw_spr("shadow", 1, 0, s.pos + Vector2(0, 4), o.g.PX * k)
	return true


# ---------------------------------------------------------------- 程序 fx 条目（§5.6 追加；纯画面，只用 g.vrng）

static func mf_is(f) -> bool:
	if not (f is Dictionary):
		return false
	for k in MF_FX_KINDS:
		if f.has(k):
			return true
	return false


## 一个数值：数字原样；[lo, hi] 取 g.vrng 区间随机
static func _mf_num(g, v) -> float:
	if v is Array and v.size() == 2:
		return g.vrng.randf_range(float(v[0]), float(v[1]))
	return float(v)


## 条目的落点列表（at：center = 出手 / 区域中心、self、leader、hits = 每个命中的敌人、summon = 本干员的每个召唤物）
static func _mf_points(o, f: Dictionary, ctx: Dictionary) -> Array:
	var g = o.g
	var out: Array = []
	match str(f.get("at", "center")):
		"self":
			out.append(o.pos)
		"leader":
			out.append(g.ppos)
		"hits":
			var cap: int = int(f.get("max_pts", 0))   # max_pts：最多在前几个命中点播（浊心歌声纹：一次领域命中十几个，只挑几个）
			for e in ctx.get("hits", _EA):
				if cap > 0 and out.size() >= cap:
					break
				out.append(e.pos + Vector2(0, -float(e.r) * 0.5))
		"summon":
			if not o.sm.is_empty():
				for s in o.sm.list:
					out.append(s.pos)
		_:
			out.append(ctx.get("c", o.pos))
	var res: Array = []
	var ov = f.get("off", [])
	var off := Vector2(float(ov[0]), float(ov[1])) if ov is Array and ov.size() == 2 else Vector2.ZERO
	if f.get("face_x", false):
		off.x *= o.face
	var al: float = float(f.get("along", 0.0)) * float(f.get("r_mult", 1.0))
	var sx: float = float(f.get("side_x", 0.0)) * float(f.get("r_mult", 1.0))
	var rch: float = float(ctx.get("reach", ctx.get("r", 0.0)))
	var dir := Vector2.from_angle(float(ctx.get("ang", 0.0)))
	for p in out:
		if p == Vector2.INF:
			continue
		res.append(p + off + dir * rch * al + Vector2(float(ctx.get("sd", 1.0)) * rch * sx, 0))
	return res


## 播一个程序条目。ctx：c（中心）、r（半径）、hits、ang、sd（这一击朝左右）、reach、half、second、swing、s（召唤物）
static func mf_fx_spawn(o, f: Dictionary, ctx: Dictionary) -> void:
	var g = o.g
	if g == null:
		return
	if f.has("pause"):
		o.impact_pause(float(f.pause))
		return
	if f.has("sfx"):
		var sv = f.sfx
		if sv is Dictionary:
			_mf_sfx(o, str(sv.get("kind", "hit")), float(sv.get("db", 0.0)), float(sv.get("pitch", 1.0)))
		else:
			_mf_sfx(o, str(sv), 0.0, 1.0)
		return
	if f.has("banner"):
		o.show_banner(str(f.banner))
		return
	if f.has("ghost") or f.has("mist") or f.has("side"):
		return   # 种类常驻画面，在 mf_draw 里画
	if f.has("pfx") and o.pfx.size() > 260:
		return
	for p in _mf_points(o, f, ctx):
		if f.has("text"):
			var tv: Dictionary = f.text if f.text is Dictionary else {"s": str(f.text)}
			o.float_text(p, str(tv.get("s", "")), _mf_col(tv.get("col", []), o.col()), int(tv.get("size", 14)))
		elif f.has("sparks"):
			var sp: Dictionary = f.sparks
			var n: int = int(round(float(sp.get("n", 5)) * (1.0 + 0.2 * o.node_lv)))
			var spd: float = float(sp.get("spd", 160.0))
			for k in n:
				o.fx({"kind": "spark", "pos": p, "vel": Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(spd * 0.4, spd),
					"life": float(sp.get("life", 0.3)) * g.vrng.randf_range(0.7, 1.2), "col": _mf_col(sp.get("col", []), o.col()), "sz": float(sp.get("sz", 2.5)), "drag": 2.0, "grav": 0.0, "floor": false})
		elif f.has("arc"):
			var ar: Dictionary = f.arc
			o.fx({"kind": "crescent", "pos": p, "ang": float(ctx.get("ang", 0.0)), "r": float(ctx.get("reach", 30.0)) + float(ar.get("pad", 0.0)),
				"w": float(ar.get("w", 5.0)), "sweep": float(ctx.get("half", 0.5)) * 2.0, "dir": float(ctx.get("sd", 1.0)), "life": float(ar.get("life", 0.2)),
				"col": _mf_col(ar.get("col", []), o.col())})
		elif f.has("sprite"):
			_mf_sprite(o, f, p, ctx)
		elif f.has("pfx") or f.has("gfx"):
			var tpl: Dictionary = f.pfx if f.has("pfx") else f.gfx
			var n2: int = int(f.get("n", 1))
			for i in n2:
				var px := _mf_particle(o, f, tpl, p, ctx, i, n2)
				if f.has("gfx"):
					px["max"] = px.life
					if str(px.get("kind", "")) == "rays":
						px["op_spoke"] = true   # 干员技能发动的放射光束（render/hit_spokes）
					g.fx.append(px)
				else:
					o.fx(px)


## 一个粒子：模板里的 [lo, hi] 取随机；jit 方框 / jit_r（× 半径的地面椭圆）散开；ring 均匀分角度（± 抖动）；vel_r 随机方向速度；
## r_scale 列出的字段 × 半径；to / to_off 给 beam / line 的终点；颜色字段是数组
static func _mf_particle(o, f: Dictionary, tpl: Dictionary, p: Vector2, ctx: Dictionary, i: int, n: int) -> Dictionary:
	var g = o.g
	var px := {}
	for k in tpl:
		var v = tpl[k]
		if k in ["col"]:
			px[k] = _mf_col(v, o.col())
		elif k == "vel" and v is Array and v.size() == 2 and v[0] is Array:
			px[k] = Vector2(_mf_num(g, v[0]), _mf_num(g, v[1]))
		elif v is Array and v.size() == 2 and (v[0] is int or v[0] is float):
			px[k] = _mf_num(g, v)
		else:
			px[k] = v
	var r: float = float(ctx.get("r", 0.0))
	for k in f.get("r_scale", _EA):
		if px.has(k):
			px[k] = float(px[k]) * r
	var q: Vector2 = p
	var jv = f.get("jit", [])
	if jv is Array and jv.size() == 4:
		q += Vector2(g.vrng.randf_range(float(jv[0]), float(jv[2])), g.vrng.randf_range(float(jv[1]), float(jv[3])))
	var jr = f.get("jit_r", [])
	if jr is Array and jr.size() == 2:
		q += Vector2(g.vrng.randf_range(-r, r) * float(jr[0]), g.vrng.randf_range(-r, r) * float(jr[1]))
	px["pos"] = q
	if f.has("ring"):
		px["ang"] = TAU * i / float(maxi(1, n)) + g.vrng.randf_range(-float(f.ring), float(f.ring))
	if f.has("vel_r"):
		var vr = f.vel_r
		var vel: Vector2 = Vector2.from_angle(g.vrng.randf() * TAU) * _mf_num(g, vr)
		px["vel"] = vel
		if f.get("ang_vel", false):
			px["ang"] = vel.angle()
	if f.has("to"):
		var tp: Vector2 = mf_at_point(o, str(f.to)) if str(f.to) != "center" else ctx.get("c", o.pos)
		var tv2 = f.get("to_off", [])
		if tv2 is Array and tv2.size() == 2:
			tp += Vector2(float(tv2[0]), float(tv2[1]))
		var tj = f.get("to_jit", [])
		if tj is Array and tj.size() == 4:
			tp += Vector2(g.vrng.randf_range(float(tj[0]), float(tj[2])), g.vrng.randf_range(float(tj[1]), float(tj[3])))
		if str(px.get("kind", "")) == "beam":
			px["a"] = q
			px["b"] = tp
		else:
			px["to"] = tp
	if not px.has("life"):
		px["life"] = 0.3
	return px


## 一次性帧条（vfx 精灵，同手写干员的 spawn_fx_sprite）：along / side_x 沿这一击的方向放；fit = [参考半径, 最小, 最大] 按攻击距离缩放、
## scale_r = 每世界像素半径的倍率（× r_mult 后的半径）；rot / second_rot / swing_rot 都乘这一击的左右（sd）；flip_side（缺省 true）：朝左时水平翻转
static func _mf_sprite(o, f: Dictionary, p: Vector2, ctx: Dictionary) -> void:
	var g = o.g
	var sv: Dictionary = f.sprite if f.sprite is Dictionary else {"name": str(f.sprite)}
	var nm: String = str(sv.get("name", ""))
	var sd: float = float(ctx.get("sd", 1.0))
	var second: bool = ctx.get("second", false)
	var rch: float = float(ctx.get("reach", ctx.get("r", 0.0)))
	var sc: float = g.PX
	var fit = sv.get("fit", [])
	if fit is Array and fit.size() == 3:
		sc = g.PX * clampf(rch / float(fit[0]), float(fit[1]), float(fit[2]))
	elif sv.has("scale_r"):
		sc = rch * float(f.get("r_mult", 1.0)) * float(sv.scale_r)
	sc *= float(sv.get("scale", 1.0)) * (float(sv.get("second_scale", 1.0)) if second else 1.0)
	var sw: float = float(ctx.get("swing", 1.0)) * (-1.0 if second else 1.0)
	var rot: float = sd * (float(sv.get("rot", 0.0)) + (float(sv.get("second_rot", 0.0)) if second else 0.0) + float(sv.get("swing_rot", 0.0)) * sw)
	if sv.get("rot_ang", false):   # 手写迁移段：随这一击的方向转（锚击刀光）
		rot = float(ctx.get("ang", 0.0))
	o.spawn_fx_sprite(nm, p, sc, rot, sv.get("flip_side", true) and sd < 0.0, sv.get("bottom", false), _mf_col(sv.get("tint", [])))


## 程序粒子的画法（data_operator._draw_pfx 转来；原凯尔希脚本的 crescent / impact / core / qshard / beamray）
static func mf_draw_pfx(o, f: Dictionary, a: float) -> bool:
	var cv = o.cv
	var P := func(v: Vector2) -> Vector2: return (v / 2.0).round() * 2.0
	match str(f.kind):
		"sk_song":
			return _F().sk_song_draw(o, f, a)   # 浊心斯卡蒂歌声命中（seg_skalter）
		"crescent":
			var u: float = 1.0 - a
			var rev: float = minf(1.0, u / 0.4)
			var half: float = f.sweep * 0.5
			var a0: float = f.ang - half * f.dir
			var a1: float = a0 + f.sweep * rev * f.dir
			var n := 16
			var outer := PackedVector2Array()
			var inner := PackedVector2Array()
			var edge := PackedVector2Array()
			for i in n + 1:
				var t: float = float(i) / n
				var an: float = lerpf(a0, a1, t)
				var th: float = f.w * sin(t * PI) * (1.0 - 0.5 * maxf(0.0, u - 0.4) / 0.6)
				var dv: Vector2 = Vector2.from_angle(an)
				var sq := Vector2(1.0, 0.8)
				outer.append(P.call(f.pos + dv * (f.r + th * 0.5) * sq))
				inner.append(P.call(f.pos + dv * (f.r - th * 0.5) * sq))
				edge.append(P.call(f.pos + dv * (f.r + th * 0.35) * sq))
			var c: Color = f.col
			if outer[0].distance_to(outer[outer.size() - 1]) > 4.0:
				for i in n:
					var q := PackedVector2Array([outer[i], outer[i + 1], inner[i + 1], inner[i]])
					if absf((q[1] - q[0]).cross(q[3] - q[0])) + absf((q[2] - q[1]).cross(q[3] - q[1])) > 2.0:
						cv.draw_colored_polygon(q, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 0.75 * a))
				cv.draw_polyline(edge, Color(2.0, 2.0, 1.9, 0.9 * a), 2.0)
			return true
		"impact":
			var k: float = 1.0 - a
			var L: float = f.r * (0.6 + 0.8 * k)
			var c2: Color = f.col
			cv.draw_circle(f.pos, f.r * (0.9 + 0.4 * k), Color(c2.r * 1.5, c2.g * 1.5, c2.b * 1.5, 0.35 * a))
			cv.draw_circle(f.pos, f.r * 0.7 * a + 2.0, Color(2.4, 2.4, 2.2, a))
			for q in 4:
				var dv2 := Vector2.from_angle(q * PI / 4.0)
				var ll: float = L * (1.0 if q % 2 == 0 else 0.6)
				cv.draw_line(f.pos - dv2 * ll, f.pos + dv2 * ll, Color(2.2, 2.2, 2.0, a), 2.0)
			return true
		"core":
			var k3: float = 1.0 - a
			var sc: float = 0.6 + 0.8 * minf(1.0, k3 * 2.5)
			var al: float = 1.0 if k3 < 0.55 else maxf(0.0, 1.0 - (k3 - 0.55) / 0.45)
			var R: float = f.r * sc
			var top: Vector2 = f.pos + Vector2(0, -R * 1.3)
			var bot: Vector2 = f.pos + Vector2(0, R * 1.3)
			var lft: Vector2 = f.pos + Vector2(-R, 0)
			var rgt: Vector2 = f.pos + Vector2(R, 0)
			var mid: Vector2 = f.pos + Vector2(R * 0.25, -R * 0.1)
			var cc: Color = f.get("col", Color(1.6, 0.16, 0.12))
			cv.draw_circle(f.pos, R * 1.8, Color(cc.r * 1.25, cc.g * 1.9, cc.b * 1.25, 0.25 * al))
			cv.draw_colored_polygon(PackedVector2Array([top, rgt, bot, lft]), Color(cc.r, cc.g, cc.b, 0.85 * al))
			cv.draw_colored_polygon(PackedVector2Array([top, mid, bot, lft]), Color(cc.r * 1.375, cc.g * 3.1, cc.b * 2.5, 0.9 * al))
			cv.draw_polyline(PackedVector2Array([top, rgt, bot, lft, top]), Color(cc.r * 1.5, cc.g * 6.2, cc.b * 5.8, al), 2.0)
			return true
		"qshard":
			var hs: float = f.sz * 0.5
			var r0: Vector2 = Vector2.from_angle(f.get("ang", 0.0)) * hs * 1.414
			var r1: Vector2 = r0.orthogonal()
			var pts := PackedVector2Array([f.pos + r0, f.pos + r1, f.pos - r0, f.pos - r1, f.pos + r0])
			var qc: Color = f.get("col", Color(1.6, 0.2, 0.1))
			cv.draw_colored_polygon(pts.slice(0, 4), Color(qc.r, qc.g, qc.b, 0.25 * a))
			cv.draw_polyline(pts, Color(qc.r * 1.375, qc.g * 2.0, qc.b * 2.0, a), 2.0)
			return true
		"beamray":
			if not Dc.hit_spokes():   # 放射光束（render/hit_spokes 缺省不画）：粒子照走寿命，只是不画
				return true
			var k4: float = 1.0 - a
			var dv3: Vector2 = Vector2.from_angle(f.ang)
			var L2: float = f.len * minf(1.0, k4 * 3.0)
			cv.draw_line(f.pos + dv3 * 10.0, f.pos + dv3 * L2, Color(f.col.r * 1.4, f.col.g * 1.6, f.col.b * 1.3, 0.6 * a), 3.0 * a + 1.0)
			return true
	return false


# ---------------------------------------------------------------- 本段的校验

## _block 转来：本段的积木（MF_TAGS）校验完返回 true
static func _mf_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in MF_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {
		"verb.summon_mod": ["skill", "sustain"],
		"verb.guard": ["skill", "instant"],
		"verb.cleanse": ["skill", "instant"],
		"trig.on_deploy": ["trig"],
	}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"verb.summon_mod":
			var k := str(b.get("kind", ""))
			var sd = ctx.get("summons", {})
			if not (sd is Dictionary) or not sd.has(k):
				errs.append("%s.kind「%s」没在 blocks.summons 里定义" % [p, k])
			var any := false
			for f in MF_MOD_FACTORS:
				if b.has(f):
					any = true
					_num(b, f, p, ctx, false, 0.1, 10.0)
			for q in ["then", "mirror"]:
				if b.has(q):
					any = true
					var v = b[q]
					if not (v is Dictionary):
						errs.append("%s.%s 必须是对象" % [p, q])
						continue
					for kk in v:
						if not kk in ["delay", "mult", "pitch", "_doc"]:
							errs.append("%s.%s.%s：只能写 delay / mult / pitch" % [p, q, kk])
					_sm_exprs(v, "%s.%s" % [p, q], ctx)
					_num(v, "mult", "%s.%s" % [p, q], ctx, true, 0.0, 5.0)
					if q == "then":
						_num(v, "delay", "%s.%s" % [p, q], ctx, true, 0.0, 2.0)
					_num(v, "pitch", "%s.%s" % [p, q], ctx, false, 0.25, 4.0)
			if b.has("lunge"):   # 精英化段：扑击（召唤物移动参数，docs/91 §6 凯尔希精一）
				any = true
				_F()._el_lunge_check(b.lunge, p + ".lunge", ctx)
			if not any:
				errs.append(p + "：verb.summon_mod 至少写 dmg / aspd / reach / arc / speed / then / mirror / lunge 之一")
			for kk in b:
				if not kk in MF_MOD_FACTORS + ["then", "mirror", "lunge", "verb", "kind", "cond", "_doc", "_uid", "_tag"]:
					errs.append("%s.%s：verb.summon_mod 不认识的字段" % [p, kk])
		"verb.guard":
			_num(b, "value", p, ctx, true, 0.0, 0.9)
			_num(b, "dur", p, ctx, true, 0.1, 60.0)
			for kk in b:
				if not kk in MF_GUARD_KEYS:
					errs.append("%s.%s：verb.guard 不认识的字段（只能是 %s）" % [p, kk, " / ".join(MF_GUARD_KEYS)])
			if b.has("look"):
				if not (b.look is Dictionary):
					errs.append(p + ".look 必须是对象")
				else:
					for kk in b.look:
						if not kk in MF_LOOK_KEYS:
							errs.append("%s.look.%s：不认识的字段（只能是 %s）" % [p, kk, " / ".join(MF_LOOK_KEYS)])
		"verb.cleanse":
			var w = b.get("what", [])
			if not (w is Array) or w.is_empty() or w.any(func(x): return not str(x) in MF_CLEANSE):
				errs.append("%s.what 必须是非空数组，取值 %s" % [p, " / ".join(MF_CLEANSE)])
		"trig.on_deploy":
			_list(b.get("do", []), p + ".do", "instant", ctx)
	return true


## 召唤物种类的扩展字段（_sm_kinds 转来）
static func _mf_kind(kd: Dictionary, p: String, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	var mv: Dictionary = kd.get("move", {}) if kd.get("move", {}) is Dictionary else {}
	var esc: bool = str(mv.get("mode", "")) == "escort"
	for k in MF_MOVE_KEYS:
		if mv.has(k) and not esc:
			errs.append("%s.move.%s 只用于 mode = escort" % [p, k])
	if esc:
		if mv.has("rest") and not (mv.rest is Array and mv.rest.size() == 2):
			errs.append(p + ".move.rest 必须是 [x, y]")
		_num(mv, "gap", p + ".move", ctx, false, 0.0, 200.0)
		_num(mv, "solid", p + ".move", ctx, false, 1.0, 60.0)
		_num(mv, "recall", p + ".move", ctx, false, 100.0, 2000.0)
		var av = mv.get("avoid", [])
		if not (av is Array) or av.any(func(x): return not str(x) in ["self", "leader"]):
			errs.append(p + ".move.avoid 只能是 self / leader 的数组")
		var a = kd.get("attack", null)
		if a is Dictionary and str(a.get("shape", "")) != "cone":
			errs.append(p + ".attack：escort 召唤物的攻击只能是 shape.cone（朝面向挥出）")
		if a is Dictionary:
			if not str(a.get("dir", "face")) in ["face", "target"]:
				errs.append(p + ".attack.dir 只能是 face / target")
			_num(a, "pad", p + ".attack", ctx, false, 0.0, 200.0)
			for q in ["origin", "fx_origin"]:
				if a.has(q) and not (a[q] is Array and a[q].size() == 2):
					errs.append("%s.attack.%s 必须是 [x, y]" % [p, q])
	if kd.has("manual") and str(kd.manual) != "command":
		errs.append(p + ".manual 只能是 command（手动普攻 B 类：按攻击键才命令它出击）")
	if kd.has("manual") and not esc:
		errs.append(p + ".manual 只用于 mode = escort")
	if kd.has("status") and not (kd.status is bool):
		errs.append(p + ".status 只能是 true / false（false = 状态条不显示在场数）")
	_num(kd, "shadow", p, ctx, false, 0.2, 4.0)
	if kd.has("float"):
		if not (kd.float is Dictionary):
			errs.append(p + ".float 必须是对象 {h, amp, hz}")
		else:
			_num(kd.float, "h", p + ".float", ctx, false, 0.0, 60.0)
			_num(kd.float, "amp", p + ".float", ctx, false, 0.0, 30.0)
			_num(kd.float, "hz", p + ".float", ctx, false, 0.0, 20.0)
	if kd.has("anim"):
		var an = kd.anim
		if not esc:   # 精英化第 5 批段：非随行召唤物也能写 anim（idle / run / attack / spawn），在 _e5_kind 里查
			pass
		elif not (an is Dictionary) or not an.has("idle"):
			errs.append(p + ".anim 必须是对象，至少有 idle")
		else:
			for k in an:
				if not k in ["idle", "run", "attack", "lunge", "leap"]:   # lunge / leap：精英化段（扑击 / 回防跃回）
					errs.append("%s.anim.%s：只能是 idle / run / attack / lunge / leap" % [p, k])
				elif not ctx.get("sprites", {}).has(str(an[k])):
					errs.append("%s.anim.%s「%s」不是本干员 sprites 里的帧条" % [p, k, str(an[k])])
	if kd.has("patch"):
		var pl = kd.patch
		if not (pl is Array) or pl.size() > 6:
			errs.append(p + ".patch 必须是数组（≤ 6 条）")
		else:
			for i in pl.size():
				var q := "%s.patch[%d]" % [p, i]
				var pe = pl[i]
				if not (pe is Dictionary):
					errs.append(q + " 必须是对象")
					continue
				for k in pe:
					if not k in MF_PATCH_KEYS:
						errs.append("%s.%s：不认识的字段（只能是 %s）" % [q, k, " / ".join(MF_PATCH_KEYS)])
				if not pe.has("cond"):
					errs.append(q + " 缺 cond（什么时候生效）")
				elif not (pe.cond is String) or parse_cond(pe.cond, ctx.base).has("err"):
					errs.append(q + ".cond 看不懂")
				_sm_exprs(pe, q, ctx)
				_num(pe, "mult", q, ctx, false, 0.0, 20.0)
				_num(pe, "speed", q, ctx, false, 0.1, 5.0)
				if pe.has("src") and not ctx.srcs.has(str(pe.src)):
					errs.append("%s.src「%s」没在 hit_sources 里登记" % [q, str(pe.src)])
				if pe.has("anim"):
					for k in pe.anim:
						if not ctx.get("sprites", {}).has(str(pe.anim[k])):
							errs.append("%s.anim.%s「%s」不是本干员 sprites 里的帧条" % [q, k, str(pe.anim[k])])
				if pe.has("seq"):
					var sq = pe.seq
					if not (sq is Dictionary) or not ctx.get("sprites", {}).has(str(sq.get("strip", ""))):
						errs.append(q + ".seq.strip 必须是本干员 sprites 里的帧条")
					elif sq.has("loop") and not (sq.loop is Array and sq.loop.size() == 2):
						errs.append(q + ".seq.loop 必须是 [首帧, 末帧]")
	if kd.has("fx"):
		_fx(kd.fx, p + ".fx", ctx, "summon")


## fx 条目里的程序条目（_fx 转来）：返回 true = 已校验
static func _mf_fx_check(f: Dictionary, q: String, ctx: Dictionary, owner: String) -> bool:
	if not mf_is(f):
		return false
	var errs: Array = ctx.errs
	var kinds: Array = MF_FX_KINDS.filter(func(k): return f.has(k))
	if kinds.size() != 1:
		errs.append("%s：程序 fx 条目恰好写一种（%s），这里有 %d 种" % [q, " / ".join(MF_FX_KINDS), kinds.size()])
		return true
	var kk: String = kinds[0]
	for k in f:
		if k != kk and not k in MF_FX_COMMON:
			errs.append("%s.%s：程序 fx 条目不认识的字段" % [q, k])
	if kk in ["ghost", "mist", "side"] and owner != "summon":
		errs.append("%s.%s 只能写在召唤物种类的 fx 里" % [q, kk])
	var at := str(f.get("at", "center"))
	if not at in MF_AT:
		errs.append("%s.at 只能是 %s" % [q, " / ".join(MF_AT)])
	if f.has("cond"):
		if not (f.cond is String) or parse_cond(f.cond, ctx.base).has("err"):
			errs.append(q + ".cond 看不懂")
	_num(f, "n", q, ctx, false, 1.0, 32.0)
	_num(f, "every", q, ctx, false, 0.03, 60.0)
	if f.has("every") and owner in FX_INSTANT_OWNERS:
		errs.append(q + ".every 只能写在常驻积木 / 召唤物种类上")
	match kk:
		"pfx", "gfx":
			var t = f[kk]
			if not (t is Dictionary):
				errs.append("%s.%s 必须是粒子模板对象" % [q, kk])
			elif not str(t.get("kind", "")) in (MF_PFX_KINDS if kk == "pfx" else MF_GFX_KINDS):
				errs.append("%s.%s.kind 只能是 %s" % [q, kk, " / ".join(MF_PFX_KINDS if kk == "pfx" else MF_GFX_KINDS)])
			else:
				for k in t:   # 数值字段：数字或 [lo, hi]（g.vrng 区间随机）
					var v = t[k]
					if v is Array and v.size() == 2 and v.all(func(x): return x is int or x is float):
						if float(v[0]) > float(v[1]):
							errs.append("%s.%s.%s：[lo, hi] 要 lo ≤ hi" % [q, kk, k])
					elif k == "life":
						_num(t, "life", "%s.%s" % [q, kk], ctx, false, 0.02, 5.0)
		"sprite":
			var sv = f.sprite
			var nm: String = str(sv.get("name", "")) if sv is Dictionary else str(sv)
			if not nm.begins_with("fx_"):
				errs.append(q + ".sprite 必须是 V6_FRAMES 里的 fx_* 帧条（字符串，或 {name, fit, scale, rot…}）")
			if sv is Dictionary:
				for k in sv:
					if k != "name" and not k in MF_SPRITE_KEYS:
						errs.append("%s.sprite.%s：不认识的字段（只能是 name / %s）" % [q, k, " / ".join(MF_SPRITE_KEYS)])
		"text":
			if not (f.text is String or f.text is Dictionary):
				errs.append(q + ".text 必须是字符串或 {s, col, size}")
		"pause":
			_num(f, "pause", q, ctx, true, 0.0, 0.2)
	return true


## shape.support（不造成伤害的普攻：every 一拍、when 条件、出手帧执行 do）
static func _mf_support(atk: Dictionary, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	for k in atk:
		if not k in ["shape", "every", "first", "when", "do", "_doc"]:
			errs.append("blocks.attack.%s：shape.support 只有 every / first / when / do" % k)
	_num(atk, "every", "blocks.attack", ctx, true, 0.1)
	_num(atk, "first", "blocks.attack", ctx, false, 0.0, 30.0)
	if atk.has("when") and (not (atk.when is String) or parse_cond(atk.when, ctx.base).has("err")):
		errs.append("blocks.attack.when 看不懂（条件串，§1.3）")
	_list(atk.get("do", []), "blocks.attack.do", "instant", ctx)
	_sm_exprs(atk, "blocks.attack", ctx)
