## 干员积木 · seg_exusiai（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_texas.gd"

# ================================================================ 能天使 exusiai（docs/61 §14，2026-10-11 第三批第四人）
# 本段只追加。积木：弹道 shape.projectile、技能外壳 dur.ammo（次数型）+ attack_patch（技能生效期间改普攻）+ end（技能结束时执行）、
# trig.on_attack（命名计数器满时，这一次普攻换成 do 里的积木）、verb.counter（命名计数器）/ verb.counter_cap（常驻：改计数器上限）/
# verb.attack_lock（之后一段时间不普攻）/ verb.ricochet（常驻：弹体命中后按概率跳向附近另一名敌人）、st.pause（短停顿，只对非精英）。
# 上面的通用代码只插了几行挂钩（都标「能天使挂钩」）；data_operator.gd 同样只插挂钩，外加末尾的绘制 / 状态两个函数。
# 运行时状态放 o.ext（data_operator 的扩展字典）：bul 弹体、cnt / cap 计数器与上限、ammo 次数型技能剩余、lock 普攻锁、burst 连射队列、was 技能上一帧是否生效。
# 确定性（docs/36 §3）：选目标按「距离 ÷ 精英优先度」再按 id 排序；只有跳弹掷 g.rng（玩法随机，docs/61 §0.4）；画面不碰 g.rng。

const EXU_IMPL := {"shape": ["projectile"], "verb": ["counter", "counter_cap", "attack_lock", "ricochet"], "st": ["pause"], "trig": ["on_attack"]}

## 每轮枪声的 [音量偏移 dB, 音高]：普攻 / 扫射 / 补射用本色；冲锋模式强力弹沉一点；过载连射每轮略轻略高（一轮 4 声，免得糊）
const EXU_SND_NORMAL := [0.0, 1.0]
const EXU_SND_AMMO := [1.5, 0.88]
const EXU_SND_BURST := [-1.5, 1.04]
const EXU_PATCH_KEYS := ["mult", "pierce", "src", "tags", "tex", "power", "burst", "burst_gap", "range_mult", "elite_prio", "last_on_hit", "muzzle_fx", "spread_deg", "focus_boss", "kb", "hit_fx"]

const EXU_BULLET_MAX := 96            # 同时在场的弹体上限（docs/59 §4：上限约 36 发/秒 × 寿命 0.7 秒）

const EXU_AIM_Y := -10.0              # 瞄准 / 判定点：敌人脚底往上 10（身体中段）

const EXU_HIT_PAD := 6.0              # 判定半径 = 敌人半径 + 6

## 弹体帧条的弹头锚点（docs/25 §6，1x 像素；@2x 自动 ×2）
const EXU_TEX_ANCHOR := {"proj_exusiai_bullet": Vector2(12, 3), "proj_exusiai_bullet_power": Vector2(15, 4),
	"proj_exusiai_bullet_s1": Vector2(15, 4), "proj_exusiai_bullet_s2": Vector2(12, 3), "proj_exusiai_bullet_s3": Vector2(12, 3)}   # 技能弹药换色帧条（docs/25 §6.1）同源帧条的锚点

## 画面帧条字段（tex 弹体 / muzzle_fx 枪口焰 / hit_fx 命中火花）：纯画面，不进结算；缺省 = 能天使的普攻那一套
const EXU_FX_KEYS := {"tex": "proj_", "muzzle_fx": "fx_", "hit_fx": "fx_"}

const EXU_ART = preload("res://scripts/art.gd")


static func exu_st(o) -> Dictionary:
	if not o.ext.has("bul"):
		o.ext.merge({"bul": [], "cnt": {}, "cap": {}, "ammo": [0, 0, 0], "lock": 0.0, "burst": [], "was": [false, false, false]})
	return o.ext


## 这名数据干员用不用得到本段（普攻是弹道，或技能带 attack_patch / end / dur.ammo）；用不到时 exu_tick 什么都不做，老数据干员逐字节不变
static func _exu_used(o) -> bool:
	if not o.ext.is_empty():
		return true
	if str(o.B.get("attack", _ED).get("shape", "")) == "projectile":
		return true
	for sb in o.B.get("skills", _EA):
		var dv = sb.get("dur", 0)
		if sb.has("end") or (dv is Dictionary and dv.has("ammo")):   # dur.next_n + attack_patch 是安洁莉娜段的落点弹，不归这里
			return true
	return false


static func _exu_main(o, b: Dictionary) -> bool:
	return int(b.get("_uid", -1)) == int(o.B.get("attack", _ED).get("_uid", -2))


## 本帧生效的某种常驻积木（成长节点 / 精英化直接写的积木，或 trig.passive 的 do 里的），按 docs/61 §5.5 的固定顺序
static func _exu_active(o, tag: String) -> Array:
	var out: Array = []
	for t in o._trigs():
		if not cond_true(o, t.get("cond", _ED)):
			continue
		if str(t.get("_tag", "")) == "trig.passive":
			for b in t.get("do", _EA):
				if str(b.get("_tag", "")) == tag and cond_true(o, b.get("cond", _ED)):
					out.append(b)
		elif str(t.get("_tag", "")) == tag:
			out.append(t)
	return out


static func _exu_cap(o, cn: String, dflt: float) -> float:
	var v := dflt
	for b in _exu_active(o, "verb.counter_cap"):
		if str(b.get("name", "")) == cn:
			v = float(b.get("value", dflt))
	return v


## 技能 attack_patch 叠到弹道参数上：mult / range_mult 相乘，power 取或，其余覆盖（src 换了 tags 也跟着换）
static func _exu_merge(p: Dictionary, patch: Dictionary) -> Dictionary:
	var q := p.duplicate()
	for k in patch:
		match str(k):
			"mult", "range_mult":
				q[k] = float(q.get(k, 1.0)) * float(patch[k])
			"power":
				q[k] = bool(q.get(k, false)) or bool(patch[k])
			_:
				q[k] = patch[k]
	return q


## 这一次射击的参数：形状自己的 + （普攻时）生效中的持续型技能 attack_patch；range / speed / muzzle / tex 缺省取普攻的
static func _exu_params(o, b: Dictionary, main: bool) -> Dictionary:
	var a: Dictionary = o.B.get("attack", {})
	var p := b.duplicate()
	for k in ["range", "speed", "muzzle", "tex"]:
		if not p.has(k) and a.has(k):
			p[k] = a[k]
	if main:
		var sk: Array = o.B.get("skills", [])
		for i in mini(3, sk.size()):
			if sk[i].has("attack_patch") and not (sk[i].get("dur", 0) is Dictionary) and (o.s_t[i] > 0.0 or o.perm_on[i]):
				p = _exu_merge(p, sk[i].attack_patch)
	return p


static func _exu_range(o, p: Dictionary) -> float:
	return float(p.get("range", 300.0)) * o.stat(&"op_range") * float(p.get("range_mult", 1.0))


static func _exu_muzzle(o, p: Dictionary) -> Vector2:
	var m = p.get("muzzle", [0.0, -30.0])
	return o.pos + Vector2(float(m[0]) * o.face, float(m[1]))


## 选目标：aim_targets（自动 = 最近，含 Boss 优先；手动 = 瞄准锥内）的候选里按「距离 ÷ 精英优先度」、再按 id 取前 n 个；
## 队友在「清杂优先」（docs/114 §13）下自动瞄准时直接用 aim_targets 的优先级顺序（不再按精英加权重排，也不把 Boss 提前）
static func _exu_targets(o, n: int, rr: float, prio: float) -> Array:
	var pool: Array = o.aim_targets(maxi(n * 3, 8), rr, o.pos)
	var mob_first: bool = o.prio_mode() == 1 and not o.held_aim()
	var ref: Vector2 = o.pos   # 距离的参照点：护航时是队长（docs/202）
	var prefer := false        # 对空优先：受控目标排最前（docs/202）
	var escorting := false
	if o.tags_all.has("verb.escort") or o.tags_all.has("verb.aim_prefer"):   # docs/202：没有这两个节点的人一条分支都不多走
		prefer = not _exu_active(o, "verb.aim_prefer").is_empty()
		var escs: Array = _exu_active(o, "verb.escort")
		if not escs.is_empty() and _exu_escort_on(o, escs[0]):
			escorting = true
			ref = o.g.ppos
			mob_first = false
			pool = []
			for j in o.query_ids(o.pos, rr):
				var ee: Dictionary = o.g.enemies[j]
				if not ee.dead and not ee.chest and ee.pos.distance_to(o.pos) <= rr:
					pool.append(ee)
		o.ext["esc_on"] = escorting
	var keyed: Array = []
	for i in pool.size():
		var e = pool[i]
		if e.dead:
			continue
		var d: float = float(i) if mob_first else ref.distance_to(e.pos)
		if (e.elite or e.boss) and not mob_first and not escorting:
			d /= maxf(1.0, prio)
		if prefer and _exu_controlled(o.g, e) and o.hittable(e):
			d -= 5.0e8
		if not o.hittable(e):
			d += 1.0e9   # 打不动的（无敌 Boss 等，op_api.hittable）垫底，只剩它们时照旧
		keyed.append([d, int(e.id), e])
	keyed.sort_custom(func(x, y): return x[0] < y[0] if x[0] != y[0] else x[1] < y[1])
	var out: Array = []
	for k in mini(n, keyed.size()):
		out.append(keyed[k][2])
	if not mob_first and not escorting and not (prefer and not out.is_empty() and _exu_controlled(o.g, out[0])) and not pool.is_empty() and pool[0].boss and o.hittable(pool[0]) and (out.is_empty() or not is_same(out[0], pool[0])):
		out.erase(pool[0])
		out.push_front(pool[0])   # 保留 op_api 的 Boss 优先（ai/boss_focus）
		if out.size() > n:
			out.resize(n)
	if not o.held_aim() and o.g.map.tb_aim and o.g.map.blocks():
		# 地形阻挡（terrain/aim_los）：自动瞄准时视线内的先（按上面的顺序补被挡的；全被挡 = 原结果）
		var all: Array = out.duplicate()
		for kv in keyed:
			if not all.has(kv[2]):
				all.append(kv[2])
		out = o.los_sort(all, n)
	return out


## 响应动作（docs/118 §4.1）aim: behind_leader：她射程内、在队长冲刺方向身后半边的敌人，按离队长由近到远（同距离按 id）取 n 个；
## 身后没有敌人退回离队长最近的（掩护队长撤出：先打追在队长身后的）
static func _exu_behind(o, n: int, rr: float) -> Array:
	var g = o.g
	var back: Vector2 = -Vector2(g.dash_dir) if Vector2(g.dash_dir) != Vector2.ZERO else Vector2(-o.face, 0.0)
	var keyed: Array = []
	for j in o.query_ids(o.pos, rr):
		var e: Dictionary = g.enemies[j]
		if e.dead or o.pos.distance_to(e.pos) > rr:
			continue
		var rel: Vector2 = e.pos - g.ppos
		keyed.append([0 if rel.dot(back) > 0.0 else 1, rel.length(), int(e.id), e])
	keyed.sort_custom(func(x, y): return x[0] < y[0] if x[0] != y[0] else (x[1] < y[1] if x[1] != y[1] else x[2] < y[2]))
	var out: Array = []
	for k in mini(n, keyed.size()):
		out.append(keyed[k][3])
	return out


## 普攻起手点（data_operator.update 的 projectile 分支）：B 需要目标类手动普攻走 attack_targets
static func exu_aim(o, a: Dictionary) -> Vector2:
	var rr: float = _exu_range(o, _exu_params(o, a, true))
	var ts: Array = o.attack_targets(1, rr, o.pos) if o.held_aim() else o.los_targets(1, rr, o.pos)
	return ts[0].pos if not ts.is_empty() else Vector2.INF


## 出手（exec_shape 的 projectile 分支）：普攻先看 trig.on_attack（计数满就换成它的 do），再按技能补丁射一轮；burst > 1 的后几轮进连射队列
static func exu_fire(o, b: Dictionary) -> void:
	var st := exu_st(o)
	var main := _exu_main(o, b)
	if main:
		if not o.attack_phased:
			o.attack_t = minf(o.attack_t, maxf(0.0, o.cd))   # 旧动作路径；阶段普攻已在起手时压缩，保留其收势下限。
		for t in o._trigs():
			if str(t.get("_tag", "")) != "trig.on_attack" or not cond_true(o, t.get("cond", _ED)):
				continue
			var cn := str(t.get("counter", ""))
			var need: float = float(t.need) if t.has("need") else float(st.cap.get(cn, INF))
			if float(st.cnt.get(cn, 0.0)) >= need:
				if t.get("reset", true):
					st.cnt[cn] = 0.0
				o._exec_list(t.get("do", []))
				o._sfx_op("big")
				if t.get("replace", true):
					return
	var p := _exu_params(o, b, main)
	var burst: int = int(p.get("burst", 1))
	_exu_volley(o, p, main, burst <= 1)
	if burst > 1:
		st.burst.append({"t": float(p.get("burst_gap", 0.06)), "left": burst - 1, "p": p, "main": main})


## 次数型技能的 attack_patch（剩余发数 > 0 的第一个）：[技能序号, 补丁]；没有 [-1, {}]
static func _exu_ammo_patch(o) -> Array:
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		if sk[i].get("dur", 0) is Dictionary and sk[i].has("attack_patch") and int(o.ext.ammo[i]) > 0:
			return [i, sk[i].attack_patch]
	return [-1, {}]


## 射一轮：n 发（普攻乘 op_shots），各自独立索敌（最近的 n 个不同目标，不够时同一目标按 ±spread 错开）；fan = 朝最近目标的扇形均布；
## focus_boss = 头号目标是 Boss 时 n 发全打它
static func _exu_volley(o, p: Dictionary, main: bool, last: bool) -> void:
	var g = o.g
	var st := exu_st(o)
	if o.pos == Vector2.INF:
		return
	var n: int = int(p.get("shots", 1))
	if main or p.get("op_shots", false):   # op_shots: true = 非普攻的一轮也按子弹数属性（响应动作的补射，发数同普攻）
		n = int(round(float(n) * o.stat(&"op_shots")))
	n = clampi(n, 1, 12)
	var fan: bool = p.get("fan", false)
	var ts: Array = _exu_behind(o, n, _exu_range(o, p)) if str(p.get("aim", "")) == "behind_leader" else _exu_targets(o, 1 if fan else n, _exu_range(o, p), float(p.get("elite_prio", 1.0)))
	if ts.is_empty():
		return
	if p.get("focus_boss", false) and ts[0].boss:
		ts = [ts[0]]   # 头号目标是 Boss 时全部子弹都打它（同一目标按 ±spread 错开）
	var aim0: Vector2 = ts[0].pos + Vector2(0, EXU_AIM_Y)
	o.face_to((aim0 - o.pos).angle())
	var mz := _exu_muzzle(o, p)
	var d0: Vector2 = (aim0 - mz).normalized() if aim0.distance_to(mz) > 1.0 else Vector2(o.face, 0.0)
	var sp: float = deg_to_rad(float(p.get("spread_deg", 0.0)))
	var speed: float = maxf(60.0, float(p.get("speed", 520.0)))
	var ap: Array = _exu_ammo_patch(o) if main else [-1, {}]
	var mfx: String = str(p.get("muzzle_fx", "fx_exusiai_muzzle"))
	var ammo_round := false   # 这一轮用的是冲锋模式的强力弹（只看第一发，同枪口焰）
	var esc_kb := 0.0         # docs/202 护航射击：被围时子弹额外击退
	var trb: Dictionary = {}  # docs/202 曳光弹：verb.tracer 积木（每 every 发一枚）
	if main and (o.tags_all.has("verb.escort") or o.tags_all.has("verb.tracer")):
		if bool(o.ext.get("esc_on", false)):
			for esc in _exu_active(o, "verb.escort"):
				esc_kb = float(esc.get("kb", 0.0))
		var trs: Array = _exu_active(o, "verb.tracer")
		if not trs.is_empty():
			trb = trs.back()   # 收网（5A）排在曳光弹（4A）之后，取它的 max
	for k in n:
		var q := p
		if ap[0] >= 0 and int(st.ammo[ap[0]]) > 0:
			q = _exu_merge(p, ap[1])
			st.ammo[ap[0]] = int(st.ammo[ap[0]]) - 1
			if k == 0:
				ammo_round = true
				mfx = str(q.get("muzzle_fx", mfx))   # 次数型技能的补丁是逐发合并的：枪口焰跟第一发子弹走（冲锋模式的青色焰）
		var dir: Vector2
		var btex: String = str(q.get("tex", ""))
		if fan:
			dir = d0.rotated(lerpf(-sp, sp, float(k) / float(n - 1)) if n > 1 else 0.0)
		else:
			var e: Dictionary = ts[k % ts.size()]
			btex = el_stack_tex(o, str(q.get("src", "")), e, btex)   # 精英化段（st.stack）：瞄准的敌人身上的层数决定弹体颜色
			var rep: int = k / ts.size()
			var off: float = sp * float((rep + 1) / 2) * (1.0 if rep % 2 == 1 else -1.0)
			var to: Vector2 = e.pos + Vector2(0, EXU_AIM_Y) - mz
			dir = (to.normalized() if to.length() > 1.0 else d0).rotated(off)
		var dmg: float = o.base(str(q.get("atk_key", "atk")), 0.0) * float(q.get("mult", 1.0)) * float(o.loc.dmg) * o._dmg_bonus()
		if q.get("power", false):
			dmg *= o.skill_power()
		var oh: Array = q.get("on_hit", [])
		if last and q.has("last_on_hit"):
			oh = oh + q.last_on_hit
		var tr_b: Dictionary = {}
		if not trb.is_empty():
			st["tr_n"] = int(st.get("tr_n", 0)) + 1
			if int(st.tr_n) % maxi(1, int(trb.every)) == 0:
				tr_b = trb
				btex = "proj_exusiai_bullet_t3"   # 曳光弹：金色弹体
		if st.bul.size() < EXU_BULLET_MAX:
			st.bul.append({"p": mz, "v": dir * speed, "life": _exu_range(o, q) * 1.15 / speed, "dmg": dmg, "src": str(q.get("src", "")),
				"tags": q.get("tags", []), "pierce": o.atk_pierce(int(q.get("pierce", 0))) if main else int(q.get("pierce", 0)), "main": main, "kb": float(q.get("kb", 0.0)) + esc_kb, "hit": {}, "tex": btex, "hfx": str(q.get("hit_fx", "fx_exusiai_hit")), "on_hit": oh, "ric": true, "tr": tr_b})
	o.spawn_fx_sprite(mfx, mz + d0 * 7.0 * g.PX * 0.8, g.PX * 0.8, d0.angle())
	if not fan:
		# 枪声跟出弹同一帧：每一轮射击一声（连射的后几轮、掩护射击补射也各一声；原来整个普攻出手只在 _release_body 末尾响一声，技能连射靠发动时的预混音频）。
		# 弹匣倾泻（fan）那一下有自己的 big 音。冲锋模式强力弹低一点更沉，过载连射（burst > 1）每轮略轻免得糊
		var snd := EXU_SND_NORMAL
		if ammo_round:
			snd = EXU_SND_AMMO
		elif int(p.get("burst", 1)) > 1:
			snd = EXU_SND_BURST
		o._sfx_op("atk", snd[0], snd[1])


## 每帧（data_operator.update 在常驻积木之后调）：技能结束 → end；普攻锁；连射队列；弹体推进与命中
static func exu_tick(o, dt: float) -> void:
	if not _exu_used(o):
		return
	var st := exu_st(o)
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		var on: bool = o.s_t[i] > 0.0
		if st.was[i] and not on and sk[i].has("end"):
			o._exec_list(sk[i].end)
		st.was[i] = on
	if st.lock > 0.0:
		st.lock = maxf(0.0, st.lock - dt)
		o.no_attack = true
	if not st.burst.is_empty():
		var keep: Array = []
		for bq in st.burst:
			bq.t -= dt
			while bq.t <= 0.0 and bq.left > 0:
				bq.left -= 1
				_exu_volley(o, bq.p, bq.main, bq.left == 0)
				bq.t += maxf(0.02, float(bq.p.get("burst_gap", 0.06)))
			if bq.left > 0:
				keep.append(bq)
		st.burst = keep
	_exu_bullets(o, dt)


static func _exu_bullets(o, dt: float) -> void:
	var st: Dictionary = o.ext
	if st.bul.is_empty():
		return
	var g = o.g
	var ve: float = o.vs_elite()
	var rics: Array = _exu_active(o, "verb.ricochet")
	var ric: Dictionary = rics[0] if not rics.is_empty() else {}
	var pref: Dictionary = {}   # docs/202 对空优先
	if o.tags_all.has("verb.aim_prefer"):
		var prs: Array = _exu_active(o, "verb.aim_prefer")
		if not prs.is_empty():
			pref = prs[0]
	var spawn: Array = []
	for bu in st.bul:
		bu.p += bu.v * dt
		bu.life -= dt
		if bu.life <= 0.0:
			continue
		var q: Vector2 = bu.p - Vector2(0, EXU_AIM_Y)
		if g.map.tb_bul and g.map.bullet_blocked(bu, q):   # 地形阻挡：弹道（含跳弹）撞景物底座即消失
			bu.life = 0.0
			bu["_die"] = "rock"   # 消失原因（只给画面，render/bullet_fx.gd）
			continue
		for j in o.query_ids(q, 32.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or bu.hit.has(e.id) or e.pos.distance_to(q) > float(e.r) + EXU_HIT_PAD:
				continue
			var pm: float = o.atk_pierce_mult(bu.hit.size()) if bu.get("main", false) else 1.0   # 穿甲弹：每穿过一名 −15%（10-23）
			bu.hit[e.id] = true
			var was_ctrl: bool = not pref.is_empty() and bu.get("main", false) and _exu_controlled(g, e)   # docs/202：打中时它已受控
			var sk: Array = el_stack_hit(o, e, str(bu.src))   # 精英化段（st.stack）：[伤害倍率, 满层命中火花（"" = 照旧）]
			o.log_hit(bu.src, bu.tags)
			o.deal_damage(e, bu.dmg * (ve if e.elite or e.boss else 1.0) * float(sk[0]) * pm)
			if not e.dead and g.rfx.sniper_execute(e, g.hit):   # 藏品 #169 扼喉之手：狙击攻击直接处决低血敌人（同维什戴尔 _h4_explode 的门槛与写法；10-15 补漏接）
				o.log_hit("真实")
				o.deal_damage(e, e.hp + 1.0)
			if float(bu.get("kb", 0.0)) > 0.0 and not e.dead and not e.boss:
				o.apply_kb(e, bu.v.normalized() * float(bu.kb) * (0.3 if e.elite else 1.0))   # 同 melee_hit：精英 ×0.3、Boss 不受
			for s in bu.on_hit:
				apply_status(o, e, s)
			if was_ctrl:   # 对空优先：打中受控目标命中即停（不再穿透），目标追加定身 pin 秒（精英减半，Boss 除外；同一敌人 1 秒内至多一次）
				bu.pierce = 0
				if not e.dead and not e.boss and g.t - float(e.get("exu_pin", -99.0)) >= 1.0:
					e["exu_pin"] = g.t
					o.add_cc_growth(e, float(pref.pin) * (0.5 if e.elite else 1.0))
					o.fx({"kind": "ring", "pos": e.pos, "r": float(e.r) + 14.0, "r0": float(e.r), "life": 0.25, "col": Color(1.0, 0.85, 0.35), "w": 2.5, "alpha": 0.95})
			if not e.dead and not bu.get("tr", {}).is_empty():   # 曳光弹命中：标记
				_exu_mark(o, e, bu.tr)
			o._sfx_op("hit")
			o.spawn_fx_sprite(str(sk[1]) if str(sk[1]) != "" else str(bu.get("hfx", "fx_exusiai_hit")), e.pos + Vector2(0, EXU_AIM_Y), g.PX * 0.8)
			if bu.ric and not ric.is_empty() and g.rng_op.randf() < float(ric.get("chance", 0.0)):
				var nx = _exu_next(o, e, float(ric.get("r", 120.0)))
				if nx != null:
					var from: Vector2 = e.pos + Vector2(0, EXU_AIM_Y)
					var spd: float = bu.v.length()
					spawn.append({"p": from, "v": (nx.pos + Vector2(0, EXU_AIM_Y) - from).normalized() * spd, "life": float(ric.get("r", 120.0)) * 1.4 / spd,
						"dmg": bu.dmg * float(ric.get("mult", 0.5)), "src": str(ric.get("src", "")), "tags": [], "pierce": 0, "hit": {e.id: true},
						"tex": bu.tex, "hfx": bu.get("hfx", "fx_exusiai_hit"), "on_hit": [], "ric": false})
			if bu.pierce > 0:
				bu.pierce -= 1
			else:
				bu.life = 0.0
				break
	st.bul = st.bul.filter(func(x): return x.life > 0.0)
	for s in spawn:
		if st.bul.size() < EXU_BULLET_MAX:
			st.bul.append(s)


## 跳弹目标：被打中的敌人 r 内离它最近的另一名活着的敌人（同距离按 id）
static func _exu_next(o, from_e: Dictionary, r: float):
	var best = null
	var bd := INF
	for j in o.query_ids(from_e.pos, r):
		var e: Dictionary = o.g.enemies[j]
		if e.dead or is_same(e, from_e):
			continue
		var d: float = e.pos.distance_to(from_e.pos)
		if d <= r and (d < bd or (d == bd and int(e.id) < int(best.id))):
			bd = d
			best = e
	return best


## 怪物密度的击杀权重（docs/50 §16.8）：enemy/density_kill_comp > 0 时，密度缩放过的普通怪按 e.dk（= 1/k）计，
## 让「按击杀次数」的积木期望总触发量不变；= 0 时一律 1（原行为）
static func kill_weight(g, e: Dictionary) -> float:
	if MfBal.v("enemy/density_kill_comp", 0.0) <= 0.0:
		return 1.0
	return float(e.get("dk", 1.0))


## 瞬时积木（data_operator._exec_list 的缺省分支）：shape.projectile / verb.counter / verb.attack_lock
static func exu_exec(o, b: Dictionary, at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"shape.projectile":
			exu_fire(o, b)
		"verb.counter":
			var st := exu_st(o)
			var cn := str(b.get("name", ""))
			if b.get("own", false) and str(o.g.hit.get("op", "")) != o.id:
				return
			var cap := _exu_cap(o, cn, float(b.get("cap", INF)))
			st.cap[cn] = cap
			if b.has("set"):
				st.cnt[cn] = minf(cap, float(b.set))
				return
			var add: float = float(b.get("add", 1.0))
			if b.has("add_lit") and at != Vector2.INF and at.distance_to(o.g.ppos) <= o.lamp_radius():
				add = float(b.add_lit)
			add *= float(o.kill_w)   # 击杀触发时按击杀权重（密度 0.4 下一只算 2.5 只）；非击杀触发时 kill_w = 1
			st.cnt[cn] = minf(cap, float(st.cnt.get(cn, 0.0)) + add)
			if b.has("text"):   # docs/202 曳光弹·收网：弹匣格金色闪动 + 飘字
				var gold := Color(1.0, 0.85, 0.35)
				o.float_text(o.pos + Vector2(0, -78), "%s +%d" % [str(b.text), int(round(add))], gold, 14)
				o.fx({"kind": "ring", "pos": o.pos + Vector2(0, -30), "r": 26.0, "r0": 8.0, "life": 0.3, "col": gold, "w": 3.0, "alpha": 0.95})
		"verb.attack_lock":
			var st2 := exu_st(o)
			st2.lock = maxf(float(st2.lock), float(b.get("dur", 0.0)))


## 技能外壳 dur.ammo（data_operator._release_skill）：装填 N 发，打完为止；HUD 环显示剩余 / 总数
static func exu_skill_shell(o, i: int, dv: Dictionary) -> void:
	var st := exu_st(o)
	st.ammo[i] = int(dv.get("ammo", 0))
	o.s_dur[i] = float(st.ammo[i])


static func exu_ammo_left(o, i: int) -> float:
	return float(o.ext.ammo[i]) if o.ext.has("ammo") else 0.0


## 画弹体（data_operator._draw_skill_over）：帧条按速度方向旋转；计数器满（下一发换成 trig.on_attack）时枪口一点金光
static func exu_draw(o) -> void:
	if o.ext.is_empty() or o.pos == Vector2.INF:
		return
	var g = o.g
	var fr: int = int(g.t * 20.0) % 2
	var bfx = g.world.bulfx
	bfx.observe("exu:" + str(o.id), o.ext.bul, "p", false, true, Color(1.0, 0.82, 0.5))   # 子弹出现 / 到期画面（命中有 fx_exusiai_hit，不叠）
	for bu in o.ext.bul:
		var tn: String = str(bu.tex)
		var tx = g.tex.get(tn) if tn != "" else null
		if tx != null:
			var an: Vector2 = EXU_TEX_ANCHOR[tn] * EXU_ART.hires_of(tx) if EXU_TEX_ANCHOR.has(tn) else Vector2(-1, -1)
			o.draw_spr_rot(tn, fr, bu.p, bu.v.angle(), g.PX * bfx.k(bu), Color.WHITE, an)
		else:
			o.cv.draw_line(bu.p - bu.v.normalized() * 12.0, bu.p, Color(1.0, 0.45, 0.45, 0.85), 3.0)
	if o.tags_all.has("verb.tracer") or o.tags_all.has("verb.escort") or o.tags_all.has("verb.aim_prefer"):
		exu_gm_draw(o)   # docs/202
	for t in o._trigs():
		if str(t.get("_tag", "")) == "trig.on_attack":
			var cn := str(t.get("counter", ""))
			var need: float = float(t.need) if t.has("need") else float(o.ext.cap.get(cn, INF))
			if float(o.ext.cnt.get(cn, 0.0)) >= need:
				var mz := _exu_muzzle(o, o.B.get("attack", {}))
				var k: float = 0.5 + 0.5 * sin(g.t * 10.0)
				o.cv.draw_circle(mz, 5.0 + 2.0 * k, Color(1.0, 0.8, 0.3, 0.35 + 0.2 * k))
				o.cv.draw_circle(mz, 2.5, Color(1.0, 0.95, 0.7, 0.9))


## Tab / 头像下的状态条：次数型技能剩余、计数器（label 或名字）、普攻锁
static func exu_status_items(o) -> Array:
	var out: Array = []
	if o.ext.is_empty():
		return out
	for i in 3:
		if int(o.ext.ammo[i]) > 0:
			out.append(["%s ×%d" % [str(o.skill_def(i).get("name", "")), int(o.ext.ammo[i])], Color(1.0, 0.8, 0.45)])
	for cn in o.ext.cnt:
		var lbl: String = cn
		for b in _exu_trig_counters(o):
			if str(b.get("name", "")) == cn and b.has("label"):
				lbl = str(b.label)
		out.append(["%s %d/%d" % [lbl, int(o.ext.cnt[cn]), int(o.ext.cap.get(cn, 0.0))], Color(1.0, 0.85, 0.4)])
	if float(o.ext.lock) > 0.0:
		out.append(["过热", Color(1.0, 0.45, 0.35)])
	return out


static func _exu_trig_counters(o) -> Array:
	var out: Array = []
	for t in o._trigs():
		for b in t.get("do", _EA):
			if str(b.get("_tag", "")) == "verb.counter":
				out.append(b)
	return out


# ---------------------------------------------------------------- 能天使段的校验（_block / validate 里的挂钩调这里）

## 本段的积木：校验完返回 true（_block 不再往下走）；不是本段的返回 false
static func _exu_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	var parts := tag.split(".")
	if parts.size() != 2 or not parts[1] in EXU_IMPL.get(parts[0], []):
		return false
	var errs: Array = ctx.errs
	var instant: bool = tag in ["shape.projectile", "verb.counter", "verb.attack_lock"]
	var sustained: bool = tag in ["verb.counter_cap", "verb.ricochet"]
	match kind:
		"attack":
			if tag != "shape.projectile":
				errs.append("%s：普攻只能是伤害形状，不是「%s」" % [p, tag])
				return true
		"trig":
			if tag != "trig.on_attack":
				errs.append("%s：这里要触发积木，不是「%s」" % [p, tag])
				return true
		"on_hit":
			if tag != "st.pause":
				errs.append("%s：on_hit 里只能放 st.stun / st.slow / st.pause，不能放「%s」" % [p, tag])
				return true
		"instant", "skill":
			if not instant:
				var why: String = "常驻积木只能放在特性 / 天赋 / 成长节点（直接作节点或 trig.passive 的 do）" if sustained else "只能放在 trait / talent / progression 或 on_hit"
				errs.append("%s：「%s」不能放在这里（%s）" % [p, tag, why])
				return true
		"sustain":
			if not sustained:
				errs.append("%s：常驻列表里只能放常驻积木，「%s」是瞬时的" % [p, tag])
				return true
	match tag:
		"shape.projectile":
			_num(b, "shots", p, ctx, kind == "attack", 1.0, 12.0)
			_num(b, "range", p, ctx, kind == "attack", 20.0, 1200.0)
			_num(b, "speed", p, ctx, false, 60.0, 3000.0)
			_num(b, "spread_deg", p, ctx, false, 0.0, 90.0)
			_num(b, "pierce", p, ctx, false, 0.0, 20.0)
			_num(b, "kb", p, ctx, false, 0.0, 400.0)
			_num(b, "mult", p, ctx, false, -INF, 20.0)
			_num(b, "burst", p, ctx, false, 1.0, 8.0)
			_num(b, "burst_gap", p, ctx, false, 0.02, 1.0)
			_num(b, "elite_prio", p, ctx, false, 1.0, 100.0)
			if b.has("aim") and str(b.aim) != "behind_leader":
				errs.append(p + ".aim 只能是 behind_leader（响应动作：队长冲刺方向身后的敌人）")
			_exu_muzzle_ok(b, p, ctx)
			_exu_fx_ok(b, p, ctx)
			_src(b, p, ctx, true)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
		"verb.counter":
			if str(b.get("name", "")) == "":
				errs.append(p + " 缺 name（计数器名）")
			for k in ["add", "add_lit", "set"]:
				_num(b, k, p, ctx, false, 0.0, 99.0)
			_num(b, "cap", p, ctx, true, 1.0, 99.0)
		"verb.counter_cap":
			if str(b.get("name", "")) == "":
				errs.append(p + " 缺 name（计数器名）")
			_num(b, "value", p, ctx, true, 1.0, 99.0)
		"verb.attack_lock":
			_num(b, "dur", p, ctx, true, 0.0, 10.0)
		"verb.ricochet":
			_num(b, "chance", p, ctx, true, 0.0, 1.0)
			_num(b, "r", p, ctx, true, 1.0, 600.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_src(b, p, ctx, true)
		"st.pause":
			_num(b, "dur", p, ctx, true, 0.0, 2.0)
		"trig.on_attack":
			if str(b.get("counter", "")) == "":
				errs.append(p + " 缺 counter（看哪个计数器满了）")
			_num(b, "need", p, ctx, false, 1.0, 99.0)
			_list(b.get("do", []), p + ".do", "instant", ctx)
	return true


static func _exu_muzzle_ok(b: Dictionary, p: String, ctx: Dictionary) -> void:
	if not b.has("muzzle"):
		return
	var m = b.muzzle
	if not (m is Array) or m.size() != 2 or not (m[0] is float or m[0] is int) or not (m[1] is float or m[1] is int):
		ctx.errs.append(p + ".muzzle 应是 [x, y]（脚底为原点、朝右、世界像素）")


## tex / muzzle_fx / hit_fx：帧条名（小写字母、数字、下划线，tex 以 proj_ 开头、另两个以 fx_ 开头）；帧条要在 game.gd V6_FRAMES 登记（exusiai_blocks 场景测试查）
static func _exu_fx_ok(b: Dictionary, p: String, ctx: Dictionary) -> void:
	for k in EXU_FX_KEYS:
		if not b.has(k):
			continue
		var v = b[k]
		var re := RegEx.create_from_string("^[a-z0-9_]+$")
		if not (v is String) or not str(v).begins_with(EXU_FX_KEYS[k]) or re.search(str(v)) == null:
			ctx.errs.append("%s.%s 应是帧条名（%s…，小写字母 / 数字 / 下划线）" % [p, k, EXU_FX_KEYS[k]])


## dur.ammo：{"ammo": N}，次数型（与 permanent 互斥）
static func _exu_dur(dv: Dictionary, p: String, perm_json: bool, i: int, ctx: Dictionary) -> void:
	if perm_json:
		ctx.errs.append("skills[%d] 是 permanent，%s.dur 也要写 \"permanent\"" % [i, p])
	for k in dv:
		if k != "ammo":
			ctx.errs.append("%s.dur.%s：dur 的对象写法只有 {\"ammo\": N}（次数型）" % [p, k])
	_num(dv, "ammo", p + ".dur", ctx, true, 1.0, 99.0)


## attack_patch（技能生效期间改普攻弹道）与 end（技能结束时执行一次）
static func _exu_skill(sb: Dictionary, p: String, ctx: Dictionary, atk_shape := "") -> void:
	if sb.has("attack_patch") and not atk_shape in ["point_aoe", "shell", "thrust", "umbrella", "hammer", "foxfire", "cannon", "bash"]:   # shell / thrust / umbrella（手写迁移段）、hammer / foxfire / cannon / bash（第 4 批）的补丁由 _v_next_n 查
		var ap = sb.attack_patch
		if not (ap is Dictionary):
			ctx.errs.append(p + ".attack_patch 必须是对象")
		else:
			var dv = sb.get("dur", 0)
			if not (dv is Dictionary) and not (dv is String) and _val(dv, ctx.base) <= 0.0:
				ctx.errs.append(p + ".attack_patch 要配持续型或次数型（dur > 0 或 {\"ammo\": N}）")
			for k in ap:
				if not k in EXU_PATCH_KEYS:
					ctx.errs.append("%s.attack_patch.%s：只能改 %s" % [p, k, " / ".join(EXU_PATCH_KEYS)])
			for k in ["mult", "range_mult"]:
				_num(ap, k, p + ".attack_patch", ctx, false, 0.0, 20.0)
			_num(ap, "pierce", p + ".attack_patch", ctx, false, 0.0, 20.0)
			_num(ap, "burst", p + ".attack_patch", ctx, false, 1.0, 8.0)
			_num(ap, "burst_gap", p + ".attack_patch", ctx, false, 0.02, 1.0)
			_num(ap, "elite_prio", p + ".attack_patch", ctx, false, 1.0, 100.0)
			_num(ap, "spread_deg", p + ".attack_patch", ctx, false, 0.0, 90.0)
			_exu_fx_ok(ap, p + ".attack_patch", ctx)
			if ap.has("src"):
				_src(ap, p + ".attack_patch", ctx, true)
			_list(ap.get("last_on_hit", []), p + ".attack_patch.last_on_hit", "on_hit", ctx)
	if sb.has("end"):
		_list(sb.end, p + ".end", "instant", ctx)


# ---------------------------------------------------------------- st.stack（能天使「穿甲连射」）

## 本帧生效的 st.stack（第一块），没有 = {}
static func el_stack_block(o) -> Dictionary:
	var el = o.get("el")
	if not (el is Dictionary):
		return {}
	var bs: Array = el.get("stack_on", [])
	return bs[0] if not bs.is_empty() else {}


## 命中结算：返回 [伤害倍率, 满层火花帧条名或 ""]；不是 st.stack 的来源原样 [1.0, ""]
static func el_stack_hit(o, e: Dictionary, src: String) -> Array:
	var b := el_stack_block(o)
	if b.is_empty() or not src in b.get("src", _EA):
		return [1.0, ""]
	var st := el_st(o)
	var t: float = float(o.g.t)
	var cur: Array = st.stk.get(e.id, [0, -INF])
	var n: int = int(cur[0]) if t - float(cur[1]) <= float(b.decay) else 0
	var mult: float = 1.0 + float(b.per) * n
	var mx: int = int(b.max)
	n = mini(n + 1, mx)
	st.stk[e.id] = [n, t]
	if st.stk.size() > 96:   # 过期 / 死掉的清掉（只按时间，确定性）
		for k in st.stk.keys():
			if t - float(st.stk[k][1]) > float(b.decay):
				st.stk.erase(k)
	return [mult, str(b.get("full_fx", "")) if n >= mx else ""]


## 开火时的弹体帧条：瞄准的敌人身上当前层数分档（0 层 = 原帧条；缺图 = 原帧条）
static func el_stack_tex(o, src: String, e: Dictionary, dflt: String) -> String:
	var b := el_stack_block(o)
	if b.is_empty() or not src in b.get("src", []) or not b.has("tex"):
		return dflt
	var cur: Array = o.el.stk.get(e.id, [0, -INF])
	if float(o.g.t) - float(cur[1]) > float(b.decay) or int(cur[0]) <= 0:
		return dflt
	var tl: Array = b.tex
	var tier: int = clampi(int(ceil(float(cur[0]) / float(b.max) * tl.size() - 0.001)), 1, tl.size())
	var nm: String = str(tl[tier - 1])
	return nm if o.g.tex.get(nm) != null else dflt


# ================================================================ docs/202 成长节点（10-29）：能天使「对空优先」「护航射击」「曳光弹」「曳光弹·收网」
## 积木都是常驻的（_exu_active 读）：verb.aim_prefer（受控目标优先）/ verb.escort（队长被围时护航）/ verb.tracer（曳光弹标记）。
## 运行时状态放 o.ext：tr_n 普攻子弹计数、marks 曳光标记 [{e, t}]、esc_on 本轮护航是否生效（_exu_targets 写、_exu_volley 读）。
## 确定性：不取随机数（目标排序按距离 / id）；画面只用 pfx 与 exu_draw 里的程序图形。

const EXU_MARK_HARD := 6   # 曳光标记的硬上限（4A 无上限设计，防实体失控；5A 的上限由积木 max 给）

static func _exu_gm_validate(b: Dictionary, p: String, ctx: Dictionary, tag: String) -> void:
	match tag:
		"verb.aim_prefer":
			_num(b, "pin", p, ctx, true, 0.0, 2.0)
		"verb.escort":
			_num(b, "r", p, ctx, true, 30.0, 600.0)
			_num(b, "n", p, ctx, true, 1.0, 30.0)
			_num(b, "kb", p, ctx, false, 0.0, 300.0)
		"verb.tracer":
			_num(b, "every", p, ctx, true, 2.0, 60.0)
			_num(b, "secs", p, ctx, true, 0.5, 30.0)
			_num(b, "bonus", p, ctx, true, 0.0, 2.0)
			_num(b, "max", p, ctx, false, 1.0, 12.0)


## 受控：眩晕 / 浮空 / 失重中（她的子弹优先打这些）
static func _exu_controlled(g, e: Dictionary) -> bool:
	return float(e.get("stun", 0.0)) > 0.0 or float(e.get("air", 0.0)) > 0.0 or float(e.get("wl_t", 0.0)) > g.t   # get：按住瞄准的伪目标（aim_point_target）没有 stun


## 护航：队长 r 内活着的敌人 ≥ n（被围）
static func _exu_escort_on(o, esc: Dictionary) -> bool:
	if o.g.ppos == Vector2.INF:
		return false
	var r: float = float(esc.r)
	var n := 0
	for j in o.query_ids(o.g.ppos, r + 40.0):
		var e: Dictionary = o.g.enemies[j]
		if not e.dead and not e.chest and e.pos.distance_to(o.g.ppos) <= r:
			n += 1
	return n >= int(esc.n)


## 曳光标记：命中的敌人标 secs 秒（队友 combat.damage 读 tr_t / tr_v / tr_op）；同时存在的标记超过 max 时最早的先摘掉
static func _exu_mark(o, e: Dictionary, tr: Dictionary) -> void:
	var g = o.g
	e["tr_t"] = g.t + float(tr.secs)
	e["tr_v"] = float(tr.bonus)
	e["tr_op"] = o.id
	var marks: Array = o.ext.get("marks", [])
	marks = marks.filter(func(m): return not is_same(m, e) and not m.dead and float(m.get("tr_t", 0.0)) > g.t)
	marks.append(e)
	var cap: int = mini(int(tr.get("max", EXU_MARK_HARD)), EXU_MARK_HARD)
	while marks.size() > cap:
		var old: Dictionary = marks.pop_front()
		old["tr_t"] = 0.0
	o.ext["marks"] = marks
	o.fx({"kind": "ring", "pos": e.pos, "r": float(e.r) + 12.0, "r0": float(e.r), "life": 0.3, "col": Color(1.0, 0.85, 0.35), "w": 2.5, "alpha": 0.95})


## 画面（exu_draw 末尾调）：曳光标记 = 金色细线连到目标 + 头顶菱形；护航生效 = 队长脚下一圈青色虚环；对空优先 = 受控目标头顶金色括号
static func exu_gm_draw(o) -> void:
	var g = o.g
	var cv = o.cv
	var marks: Array = o.ext.get("marks", [])
	if not marks.is_empty():
		var mz := _exu_muzzle(o, o.B.get("attack", {}))
		for e in marks:
			if e.dead or float(e.get("tr_t", 0.0)) <= g.t:
				continue
			var a: float = clampf((float(e.tr_t) - g.t) / 0.5, 0.0, 1.0)
			var tp: Vector2 = e.pos + Vector2(0, EXU_AIM_Y)
			cv.draw_line(mz, tp, Color(1.0, 0.85, 0.35, 0.38 * a), 1.0)
			var top: Vector2 = e.pos + Vector2(0, -float(e.r) - 16.0)
			cv.draw_colored_polygon(PackedVector2Array([top + Vector2(0, -6), top + Vector2(5, 0), top + Vector2(0, 6), top + Vector2(-5, 0)]), Color(1.0, 0.85, 0.35, 0.9 * a))
	if bool(o.ext.get("esc_on", false)) and g.ppos != Vector2.INF:
		var rr: float = 150.0
		for esc in _exu_active(o, "verb.escort"):
			rr = float(esc.r)
		cv.draw_set_transform(g.ppos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		cv.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 40, Color(0.5, 0.85, 1.0, 0.4 + 0.15 * sin(g.t * 6.0)), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not _exu_active(o, "verb.aim_prefer").is_empty():
		var n := 0
		for j in o.query_ids(o.pos, _exu_range(o, o.B.get("attack", {}))):
			var e: Dictionary = g.enemies[j]
			if e.dead or not _exu_controlled(g, e) or not o.hittable(e):
				continue
			var tp2: Vector2 = e.pos + Vector2(0, -float(e.r) - 12.0)
			cv.draw_polyline(PackedVector2Array([tp2 + Vector2(-6, -3), tp2 + Vector2(0, 3), tp2 + Vector2(6, -3)]), Color(1.0, 0.85, 0.35, 0.9), 1.6)
			n += 1
			if n >= 8:
				break
