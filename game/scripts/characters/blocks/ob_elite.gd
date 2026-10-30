## 干员积木 · ob_elite（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/ob_summon.gd"


# ================================================================ 精英化第 1 批（docs/91 §19 批 1、§20：德克萨斯 / 能天使 / 星熊 / 安洁莉娜 / 凯尔希，10-13）
# 只往后加。新积木：
#  st.stack          常驻（trait / talent / 节点 / passive do）：本干员 src 列表里的伤害命中同一名敌人时按层加伤——命中时伤害 × (1 + per × 已有层数)，
#                    然后层数 +1（至多 max）；这名敌人 decay 秒没被这些来源打中就清零。层数记在本干员身上（按敌人 id），不写进敌人。
#                    tex：按层数分档换弹体帧条（[1 档, 2 档, 3 档…]，层数 / max 均分；0 层用原弹体）；full_fx：叠满后这一下的命中火花。
#                    目前作用于弹道命中（shape.projectile，能天使「穿甲连射」）；逻各斯「剜魂」迁积木时接到 st.* 法伤上
#  verb.buff_timed   瞬时：stat / op（缺省 add）/ value，持续 dur 秒；同 key 再触发只刷新时间、不叠加。生效期间等同一块 verb.buff_self 常驻积木
#                    （局部倍率或 op_* 属性，fx 里的贴身层 / hold 帧条也照常画），条件 buff:<key> 为真。星熊「反击架势」
#  shape.boomerang   瞬时：往返弹体。朝最近敌人（按住瞄准按 A 方向）飞出 len（× op_range），到头停 hold 秒，再飞回本干员手里（原点跟着她走）；
#                    去程、回程各扫一遍线段（宽 w），同一敌人每程一次：去程 × mult_out 并按 kb_out 击退，回程 × mult_back 不击退。伤害口径同 shape.line
#                    （普攻替换时也吃局部倍率 atk）。lock: true = 弹体在外面时本干员不普攻。tex：弹体帧条（缺图画程序圆盾）；spark：沿途火花帧条。星熊「般若回旋」
#  verb.summon_cmd   瞬时：指挥 kind 种召唤物做一个动作。action: leap = 以 t 秒弧线跃回 to（leader = 队长身边；front = 队长与最近敌群之间、队长前方，落地面朝敌群），落地执行 then（center: target = 落点）。凯尔希「回防」「护主」
#  trig.on_mate_attack  画面挂点：编队里 scope（缺省 others）范围内的队友每次普攻出手，在她的出手点播 fx（at: mate）。只有画面，不进玩法。能天使「天使的祝福」
#  trig.on_mate_hook    联动（docs/123 §2.7）：队友 op（缺省任何）的 shape.hookshot 把敌人拖回到位时，本干员在 range（× op_range）内就以落点为 target 执行 do；cd 秒一次；knob = balance.json 开关路径。乌尔比安 × 歌蕾蒂娅「钩与锚」
# 新参数（挂在已有积木上）：
#  st.* 的 first_only（只给这次命中列表 / 这次冲刺的第一个敌人）、cd（同一块状态两次生效至少隔几秒）、fx（状态生效时在这名敌人处播，中心 = 敌人脚底）
#  trig.every_n 的 replace（这一次普攻整个换成 do）/ anim（这一次起手播的帧条）
#  shape.circle 的 only（[weightless / airborne]：只打处于这些状态的敌人）、center: path + step / delay / stagger（沿上一次冲刺路径每 step 一处，依次延迟结算）
#  verb.field 的 cap；verb.dash_mod 的 on_hit；verb.trail 的 on_expire；verb.fx_rain 的 along: path / step / if_tex；verb.summon_mod 的 lunge
#  （召唤物扑击：目标在 min_d 外时 t 秒扑过去，落地半径 r 内 × mult，cd 秒一次）；召唤物 anim 的 lunge / leap 帧条
#  fx 条目的 delay / stay / once / face_x / flash: fire，at: members（光环受益者，hold）/ mate；hold 的 over 层（画在人物之上）
# 确定性：本段不取 g.rng；画面只用 g.vrng 与 g.t。没写这些积木 / 参数的干员一个分支都不走（同 seed 逐行不变）。

const EL_TAGS := ["st.stack", "verb.buff_timed", "shape.boomerang", "verb.summon_cmd", "trig.on_mate_attack", "trig.on_mate_hook"]

const EL_BOOM_MAX := 6           # 每名干员同时在外的往返弹体上限

const EL_GREEN := Color(0.55, 1.0, 0.5)


## 本段状态（data_operator.el）：timed 限时增益、stk 叠层、boom 往返弹体、cd 状态冷却、fire_t 上次普攻出手的 g.t
static func el_st(o) -> Dictionary:
	if o.el.is_empty():
		o.el.merge({"timed": {}, "stk": {}, "boom": [], "cd": {}, "fire_t": -99.0})
	return o.el


static func el_parse_cond(s: String) -> Dictionary:
	var neg := s.begins_with("!")
	var t := s.substr(1).strip_edges() if neg else s
	if t.begins_with("buff:") and t.length() > 5:
		return {"neg": neg, "k": "buff", "a": t.substr(5), "op": "", "v": 0.0}
	return {}


## 限时增益 key 生效中
static func el_buff_on(o, key: String) -> bool:
	var el = o.get("el")
	if not (el is Dictionary) or el.is_empty():
		return false
	var tb: Dictionary = el.timed
	return tb.has(key) and float(tb[key].until) > float(o.g.t)


## 只乘普攻的局部倍率（data_operator 在普攻出手的那一下把 atk_live 置 true）
static func el_atk_mult(o) -> float:
	if o.get("atk_live") == true:
		return float(o.loc.get("atk", 1.0))
	return 1.0


## st.* 的 first_only / cd 闸门：idx = 这名敌人在这次命中列表里的序号（-1 = 没有顺序，first_only 不生效）
static func el_status_gate(o, s: Dictionary, idx: int) -> bool:
	if s.get("first_only", false) and idx != 0:
		return false
	if s.has("nearest_n") and idx >= int(s.nearest_n):
		return false
	if s.has("cd"):
		var st := el_st(o)
		var u: int = int(s.get("_uid", 0))
		if float(st.cd.get(u, -INF)) > float(o.g.t):
			return false
		st.cd[u] = float(o.g.t) + float(s.cd)
	return true


## shape.circle only：圆内（同 area_hit 的判定）且处于 only 列出的状态之一的敌人，伤害同 area_hit（× vs_elite），不击退不眩晕
static func el_area_only(o, b: Dictionary, c: Vector2, r: float, dmg: float) -> Array:
	var g = o.g
	var only: Array = b.get("only", [])
	var hits: Array = []
	for e in o.arc_targets(c, 0.0, PI, r):
		if e.dead:
			continue
		var ok := false
		for k in only:
			match str(k):
				"weightless":
					ok = ok or (e.has("wl_t") and float(e.wl_t) > float(g.t))
				"airborne":
					ok = ok or float(e.get("air", 0.0)) > 0.0 or o.air_list.any(func(a): return is_same(a.e, e))
		if ok:
			hits.append(e)
	var max_n: int = int(b.get("max_n", 0))
	if max_n > 0 and hits.size() > max_n:
		hits = o.cap_targets(hits, c, max_n)
	var ve: float = o.vs_elite()
	var src: String = str(b.get("src", ""))
	var tags: Array = b.get("tags", [])
	for e in hits:
		o.log_hit(src, tags)
		o.deal_damage(e, dmg * (ve if e.elite or e.boss else 1.0))
	return hits


## 路径上的点：from → to 均分 ceil(长 / step) 段，取各段中点
static func el_path_points(a: Vector2, b: Vector2, step: float) -> Array:
	var L: float = a.distance_to(b)
	var n: int = maxi(1, int(ceil(L / maxf(1.0, step) - 0.001)))
	var out: Array = []
	for i in n:
		out.append(a.lerp(b, (float(i) + 0.5) / float(n)))
	return out


## shape.circle center: path：沿德克萨斯段的上一次冲刺 / 残像路径（tx.ctx）每 step 一处；第 i 处在 delay + i × stagger 秒后结算（进冲刺延迟队列）
static func el_path_circles(o, b: Dictionary) -> void:
	var c: Dictionary = o.tx.get("ctx", {})
	if not c.has("from"):
		return
	var pts: Array = el_path_points(c.from, c.to, float(b.get("step", 40.0)))
	var d0: float = float(b.get("delay", 0.0))
	var st: float = float(b.get("stagger", 0.0))
	for i in pts.size():
		var b2: Dictionary = b.duplicate()
		b2["center"] = "target"
		b2.erase("cond")   # 条件在整块执行时已经看过
		var dl: float = d0 + st * i
		if dl <= 0.0:
			exec_shape(o, b2, pts[i])
		else:
			var q: Array = o.tx.get("queue", [])
			q.append({"t": dl, "do": [b2], "ctx": {"to": pts[i]}})
			o.tx["queue"] = q


# ---------------------------------------------------------------- 常驻部分（data_operator._sustain 转来）

## 本帧生效的限时增益积木（按 key 首次触发的顺序，确定性）追加进常驻列表；同时记下本帧的 st.stack
static func el_sustain_collect(o, act: Array) -> void:
	var el = o.get("el")
	var has_sk: bool = has_tag(o, "st.stack")   # B6 ④：没有 st.stack 的干员不逐块找
	if not (el is Dictionary) or el.is_empty():
		for b in (act if has_sk else _EA):
			if str(b.get("_tag", "")) == "st.stack":
				el_st(o)
				break
		if o.el.is_empty():
			return
	var t: float = float(o.g.t)
	for k in o.el.timed.keys():
		var tb: Dictionary = o.el.timed[k]
		if float(tb.until) > t:
			act.append(tb.b)
		else:
			o.el.timed.erase(k)
	var sk: Array = []
	for b in (act if has_sk else _EA):
		if str(b.get("_tag", "")) == "st.stack":
			sk.append(b)
	o.el["stack_on"] = sk


# ---------------------------------------------------------------- 瞬时（data_operator._exec_list 缺省分支转来）

static func el_exec(o, b: Dictionary, at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"verb.buff_timed":
			var st := el_st(o)
			var key: String = str(b.get("key", "buff"))
			var had: bool = st.timed.has(key) and float(st.timed[key].until) > float(o.g.t)
			st.timed[key] = {"until": float(o.g.t) + float(b.dur), "b": b}
			if not had and b.has("text"):
				o.float_text(o.pos + Vector2(0, -80), str(b.text), Color(1.0, 0.45, 0.4), 14)
		"shape.boomerang":
			el_boom_start(o, b)
		"verb.summon_cmd":
			el_summon_cmd(o, b, at)


# ---------------------------------------------------------------- shape.boomerang（星熊「般若回旋」）

static func el_boom_start(o, b: Dictionary) -> void:
	var g = o.g
	if o.pos == Vector2.INF:
		return
	var st := el_st(o)
	if st.boom.size() >= EL_BOOM_MAX:
		return
	var L: float = float(b.get("len", 220.0)) * o.stat(&"op_range")
	var ts: Array = o.nearest_enemies(1, L + 20.0, o.pos)
	var ang: float = o.atk_angle((ts[0].pos - o.pos).angle() if not ts.is_empty() else o.facing_angle())
	var dir := Vector2.from_angle(ang)
	if absf(dir.x) > 0.1:
		o._set_face(signf(dir.x), true)
	var dmg: float = o.base(str(b.get("atk_key", "atk")), 0.0) * float(o.loc.dmg) * o._dmg_bonus() * el_atk_mult(o)
	if b.get("power", false):
		dmg *= o.skill_power()
	st.boom.append({"b": b, "dir": dir, "L": L, "w": float(b.get("w", 56.0)), "t": 0.0, "to": float(b.get("t_out", 0.3)), "hold": float(b.get("hold", 0.1)),
		"tb": float(b.get("t_back", 0.3)), "dmg": dmg, "last": 0.0, "hit0": {}, "hit1": {}, "spin": 0.0, "sp_t": 0.0})
	if b.has("sfx"):
		o._sfx_op(str(b.sfx))


## 弹体此刻离本干员的距离（世界像素）与所在程（0 去 / 1 回）
static func _el_boom_d(bm: Dictionary) -> Array:
	var t: float = float(bm.t)
	var to: float = float(bm.to)
	if t < to:
		var k: float = t / maxf(0.01, to)
		return [float(bm.L) * (1.0 - (1.0 - k) * (1.0 - k)), 0]   # 先快后慢
	if t < to + float(bm.hold):
		return [float(bm.L), 0]
	var k2: float = clampf((t - to - float(bm.hold)) / maxf(0.01, float(bm.tb)), 0.0, 1.0)
	return [float(bm.L) * (1.0 - k2 * k2), 1]   # 先慢后快地收回


static func el_boom_total(bm: Dictionary) -> float:
	return float(bm.to) + float(bm.hold) + float(bm.tb)


## 每帧（data_operator.update）：推进往返弹体、扫线段结算
static func el_tick(o, dt: float) -> void:
	var el = o.get("el")
	if not (el is Dictionary) or el.is_empty() or el.boom.is_empty() or o.pos == Vector2.INF:
		return
	var g = o.g
	for bm in el.boom:
		var d0: Array = _el_boom_d(bm)
		bm.t = float(bm.t) + dt
		bm.spin = float(bm.spin) + dt * 18.0
		var d1: Array = _el_boom_d(bm)
		var b: Dictionary = bm.b
		var leg: int = int(d1[1])
		if leg != int(d0[1]):   # 刚转回程：去程的最后一段补扫
			_el_boom_sweep(o, bm, float(d0[0]), float(bm.L), 0)
			d0 = [float(bm.L), 1]
		_el_boom_sweep(o, bm, float(d0[0]), float(d1[0]), leg)
		bm.sp_t = float(bm.sp_t) - dt
		if float(bm.sp_t) <= 0.0 and b.has("spark"):   # 沿途火花（画面）
			bm.sp_t = 0.06
			var p: Vector2 = o.pos + bm.dir * float(d1[0]) + Vector2(0, -22)
			o.spawn_fx_sprite(str(b.spark), p + Vector2(g.vrng.randf_range(-6.0, 6.0), g.vrng.randf_range(-6.0, 6.0)), g.PX, g.vrng.randf() * TAU)
	el.boom = el.boom.filter(func(bm): return float(bm.t) < el_boom_total(bm))


## 扫 [a, c]（离本干员的距离）这一段：线段内、这一程还没打过的敌人各吃一次
static func _el_boom_sweep(o, bm: Dictionary, a: float, c: float, leg: int) -> void:
	var g = o.g
	if absf(c - a) < 0.01 and a > 0.5:
		return
	var b: Dictionary = bm.b
	var dir: Vector2 = bm.dir
	var lo: float = minf(a, c)
	var hi: float = maxf(a, c)
	var p0: Vector2 = o.pos + dir * lo
	var hit: Dictionary = bm.hit0 if leg == 0 else bm.hit1
	var mult: float = float(b.get("mult_out", 1.0)) if leg == 0 else float(b.get("mult_back", 1.0))
	var kb: float = float(b.get("kb_out", 0.0)) if leg == 0 else 0.0
	var ve: float = o.vs_elite()
	var src: String = str(b.get("src", ""))
	var tags: Array = b.get("tags", [])
	var w: float = float(bm.w)
	var got: Array = []
	for j in o.query_ids(p0 + dir * (hi - lo) * 0.5, (hi - lo) * 0.5 + w + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or hit.has(e.id) or not line_contains(p0, dir, hi - lo, w, e.pos, float(e.r)):
			continue
		hit[e.id] = true
		got.append(e)
	for e in got:
		o.log_hit(src, tags)
		o.deal_damage(e, float(bm.dmg) * mult * (ve if e.elite or e.boss else 1.0))
		if not e.dead and not e.boss and kb > 0.0:
			o.apply_kb(e, dir * kb * (0.3 if e.elite else 1.0))
		o._hit_fx(e, o.pos)
		if b.has("fx"):
			fx_play(o, b.fx, e.pos + Vector2(0, -float(e.r) * 0.5), float(e.r), [e], dir.angle())
	if not got.is_empty():
		o._sfx_op("hit")


## 普攻锁：有 lock: true 的往返弹体在外面
static func el_attack_locked(o) -> bool:
	var el = o.get("el")
	if not (el is Dictionary) or el.is_empty():
		return false
	for bm in el.boom:
		if bm.b.get("lock", false):
			return true
	return false


# ---------------------------------------------------------------- 召唤物：扑击（summon_mod.lunge）/ 跃回（verb.summon_cmd）

static func _el_dash_spec(o, kd: Dictionary, k: String) -> Dictionary:
	var key: String = str(kd.get("anim", _ED).get(k, ""))
	if key == "" or o.anim_tex(key) == null:
		return {}
	return o.sprite_spec(key)


## 起一段位移：k = lunge / leap；to = 落点；t = 位移秒数；h = 弧线高度；land = 落地时执行的 [种类, 参数]
static func _el_dash_start(o, s: Dictionary, kd: Dictionary, k: String, to: Vector2, t: float, h: float, land: Dictionary) -> void:
	var sp := _el_dash_spec(o, kd, k)
	var fps: float = float(sp.get("fps", 12.0))
	var n: float = float(sp.get("frames", 0))
	var t0 := 0.0
	var end: float = t + 0.08
	if not sp.is_empty():
		var land_t: float = (float(sp.fire) + 0.5) / fps if sp.has("fire") else (n - 2.0) / fps   # 扑击：出手帧落爪；跃回：倒数第 2 帧（展开刃爪）落地
		t0 = maxf(0.0, land_t - t)
		end = t0 + t + 1.0 / fps   # 落地后再停一帧就交还给普通行动（帧条后面的收势帧让位给紧接着的爪击，不白占出手时间）
	s.dash = {"k": k, "from": s.pos, "to": to, "t": 0.0, "t0": t0, "dur": t, "end": end, "h": h, "h_now": 0.0, "land": land, "done": false, "hist": []}
	s.act = end
	s.fire = -1.0
	s.pend = []
	if absf(to.x - s.pos.x) > 2.0:
		s.face = signf(to.x - s.pos.x)
		s.flip_t = o.g.t
	s.ak = k
	s.at = 0.0


static func el_dash_step(o, s: Dictionary, kd: Dictionary, mods: Dictionary, dt: float) -> void:
	var g = o.g
	var d: Dictionary = s.dash
	var prev: Vector2 = s.pos
	var ph: float = float(d.h_now)
	d.t = float(d.t) + dt
	var k: float = clampf((float(d.t) - float(d.t0)) / maxf(0.01, float(d.dur)), 0.0, 1.0)
	s.pos = (d.from as Vector2).lerp(d.to, 1.0 - (1.0 - k) * (1.0 - k) if d.k == "lunge" else k)
	d.h_now = float(d.h) * sin(k * PI)
	var hist: Array = d.hist
	hist.append([float(d.t), s.pos, float(d.h_now), _mf_frame(o, s, kd, str(d.k), float(d.t)), float(s.face), _mf_col(s.pcur.get("tint", []), EL_GREEN)])
	if hist.size() > 12:
		hist.pop_front()
	if d.k == "leap" and k > 0.0 and k < 1.0 and s.pos.distance_to(prev) > 0.5:   # 跃回：空中拉一道绿色弧形拖尾（逐段淡出）
		o.fx({"kind": "line", "pos": prev + Vector2(0, -ph - 52.0), "to": s.pos + Vector2(0, -float(d.h_now) - 52.0), "w": 2.0, "life": 0.18, "col": Color(EL_GREEN.r, EL_GREEN.g, EL_GREEN.b, 0.45)})
	if not d.done and float(d.t) >= float(d.t0) + float(d.dur):
		d.done = true
		_el_land(o, s, kd, mods, d)
	var cdk: float = dt
	for f in mods.aspd:
		cdk *= f
	s.cd = float(s.cd) - cdk
	s.at = float(s.at) + dt
	s.mv = 0.0
	if float(d.t) >= float(d.end):
		s.erase("dash")
		s.act = 0.0
		_mf_set_anim(s, "idle")


static func _el_land(o, s: Dictionary, kd: Dictionary, mods: Dictionary, d: Dictionary) -> void:
	var g = o.g
	var ld: Dictionary = d.land
	match str(ld.get("kind", "")):
		"lunge":
			var lg: Dictionary = ld.b
			var a: Dictionary = kd.get("attack", {})
			var r: float = float(lg.get("r", 40.0)) * o.stat(&"op_range")
			var dmg: float = mf_dmg(o, a, mods, s.pcur) * float(lg.get("mult", 0.3))
			var tags: Array = a.get("tags", []).duplicate()
			if not "summon" in tags:
				tags.append("summon")
			var hits: Array = o.area_hit(str(s.pcur.get("src", a.get("src", ""))), s.pos, r, dmg, 0.0, 0.0, tags)
			if lg.has("fx"):
				fx_play(o, lg.fx, s.pos, r, hits)
			else:
				o.fx({"kind": "ring", "pos": s.pos, "r": r, "r0": r * 0.4, "life": 0.25, "col": EL_GREEN, "floor": true, "w": 2.0, "alpha": 0.7})
		"leap":
			if ld.has("face_x") and absf(float(ld.face_x) - s.pos.x) > 2.0:   # 落地面朝敌群（背对队长）
				s.face = signf(float(ld.face_x) - s.pos.x)
				s.flip_t = g.t
			o._exec_list(ld.get("then", []), s.pos)
			var b: Dictionary = ld.get("b", {})
			if b.has("fx"):
				fx_play(o, b.fx, s.pos, 100.0)


## 扑击：目标在 min_d（+ 目标半径）外、冷却好了 → 扑到目标身前；返回 true = 已起扑
static func el_lunge_try(o, s: Dictionary, kd: Dictionary, tg: Dictionary, lg: Dictionary) -> bool:
	var g = o.g
	if float(g.t) < float(s.get("lunge_cd", -INF)):
		return false
	var dv: Vector2 = tg.pos - s.pos
	# 够得着就直接出爪：扑击只替「走过去」那一段（目标在 min_d 与爪击距离两者较大的那个之外才扑）
	var reach: float = mf_reach(o, kd.get("attack", {}), mf_mods(o, str(s.kind)))
	if dv.length() <= maxf(float(lg.get("min_d", 80.0)), reach) + float(tg.r):
		return false
	var gap: float = float(tg.r) + float(kd.get("move", _ED).get("gap", 26.0))
	var to: Vector2 = tg.pos - dv.normalized() * gap
	s.lunge_cd = float(g.t) + float(lg.get("cd", 1.5))
	_el_dash_start(o, s, kd, "lunge", to, float(lg.get("t", 0.15)), 0.0, {"kind": "lunge", "b": lg})
	return true


## verb.summon_cmd：现在只有 action leap（跃回 to 身边），to 缺省 leader
static func el_summon_cmd(o, b: Dictionary, _at: Vector2) -> void:
	var g = o.g
	if o.sm.is_empty():
		return
	if str(b.get("action", "")) == "cast":   # 精英化第 5 批段：原地施放（播 attack 帧条，出手帧执行 then）
		_F().e5_cast(o, b)
		return
	var kind: String = str(b.get("kind", ""))
	var kd := sm_kind(o, kind)
	if kd.is_empty() or str(kd.get("move", _ED).get("mode", "")) != "escort":
		return
	if str(b.get("to", "leader")) == "front":
		_el_leap_front(o, kind, kd, b)
		return
	var c: Vector2 = g.ppos if str(b.get("to", "leader")) == "leader" else o.pos
	if c == Vector2.INF:
		return
	for s in o.sm.list:
		if str(s.kind) != kind or s.gone or float(s.get("down", 0.0)) > 0.0:   # 倒地的不接指挥
			continue
		var side: float = signf(s.pos.x - c.x) if absf(s.pos.x - c.x) > 4.0 else float(o.face)
		var to: Vector2 = c + Vector2(side * float(b.get("land_dx", 30.0)), float(b.get("land_dy", 8.0)))
		_el_dash_start(o, s, kd, "leap", to, float(b.get("t", 0.25)), float(b.get("h", 46.0)), {"kind": "leap", "then": b.get("then", []), "b": b})


## to: front（10-29 用户：回跳到队长旁边像要攻击队长）：跃到队长与最近敌群之间、队长前方 d 像素处，落地面朝敌群（背对队长），落地圈以落点为中心且不罩住队长。
## d = 队长到敌群中心距离 − 20，夹在 [front_min（缺省 60）, front_max（缺省 80）]；落地圈半径封顶 d − ring_clear（缺省 16，不低于 40）。
## range（缺省 260）内没有敌人时不做扑击也不画落地圈，Mon3tr 由 escort 小步跟回队长身侧
static func _el_leap_front(o, kind: String, kd: Dictionary, b: Dictionary) -> void:
	var g = o.g
	var c: Vector2 = g.ppos
	if c == Vector2.INF:
		return
	var near: Array = g.enemies_sys.nearest(int(b.get("n", 5)), float(b.get("range", 260.0)), c)
	if near.is_empty():
		return
	var ctr := Vector2.ZERO
	for e in near:
		ctr += e.pos
	ctr /= float(near.size())
	var dv: Vector2 = ctr - c
	var dist: float = dv.length()
	var dir: Vector2 = dv / dist if dist > 1.0 else Vector2(float(o.face), 0.0)
	var d: float = clampf(dist - 20.0, float(b.get("front_min", 60.0)), float(b.get("front_max", 80.0)))
	var to: Vector2 = c + dir * d
	var then: Array = []
	for t in b.get("then", []):
		var t2: Dictionary = (t as Dictionary).duplicate() if t is Dictionary else {}
		if t2.has("r") and (t2.r is float or t2.r is int):
			t2["r"] = minf(float(t2.r), maxf(40.0, d - float(b.get("ring_clear", 16.0))))
		then.append(t2)
	for s in o.sm.list:
		if str(s.kind) != kind or s.gone or float(s.get("down", 0.0)) > 0.0:
			continue
		_el_dash_start(o, s, kd, "leap", to, float(b.get("t", 0.25)), float(b.get("h", 46.0)), {"kind": "leap", "then": then, "b": b, "face_x": ctr.x})


## 扑击 / 跃回的残影：前0.04/0.08/0.12秒的真实身体帧、面向与颜色快照，不再加载旧固定剪影。
static func el_draw_afterimages(o, s: Dictionary, kd: Dictionary, fr: Array, hov: float) -> void:
	var d: Dictionary = s.dash
	var hist: Array = d.hist
	if hist.size() < 2 or float(d.t) < float(d.t0) or float(d.t) > float(d.t0) + float(d.dur) + 0.15:
		return
	var base_h: float = hov + float(d.h_now)
	for q in [3, 2, 1]:
		var tq: float = float(d.t) - 0.04 * q
		var it: Array = hist[0]
		for h in hist:
			if float(h[0]) <= tq:
				it = h
		var p: Vector2 = it[1]
		if p.distance_to(s.pos) < 4.0:
			continue
		var al: float = 0.2 * (1.0 - 0.22 * (q - 1))
		var py: Vector2 = p + Vector2(0, base_h - float(it[2]))
		var frozen: Array = it[3] if it.size() > 3 else fr
		var flip: bool = float(it[4]) < 0.0 if it.size() > 4 else float(s.face) < 0.0
		var shade: Color = it[5] if it.size() > 5 else EL_GREEN
		if not frozen.is_empty():
			o.draw_sprite_at(py, flip != o.sprite_mirror(str(frozen[3])), Color(shade.r, shade.g, shade.b, al), frozen[1], frozen[0], frozen[2], o.foot_off(frozen[0], frozen[3]))


# ---------------------------------------------------------------- 画面（data_operator._draw_skill_over 转来）

static func el_draw_over(o) -> void:
	var g = o.g
	var el = o.get("el")
	if not (el is Dictionary) or el.is_empty() or o.pos == Vector2.INF:
		return
	for bm in el.boom:
		var d: Array = _el_boom_d(bm)
		var p: Vector2 = o.pos + bm.dir * float(d[0]) + Vector2(0, -22)
		var b: Dictionary = bm.b
		var tn: String = str(b.get("tex", ""))
		var tx = g.tex.get(tn) if tn != "" else null
		if tx != null and g.V6_FRAMES.has(tn):
			var spec: Array = g.V6_FRAMES[tn]
			fx_frame(o.cv, g, tn, int(spec[0]), int(float(bm.t) * float(spec[1])), p, g.PX * float(b.get("scale", 1.0)), Color.WHITE, Vector2(-1, -1), 0.0)
		else:   # 程序圆盾：翠绿盾面 + 外圈 + 4 道锯齿，转着飞
			var R: float = 13.0
			o.cv.draw_circle(p, R + 3.0, Color(0.03, 0.06, 0.05, 0.6))
			o.cv.draw_circle(p, R, Color(0.25, 0.75, 0.45))
			o.cv.draw_arc(p, R, 0.0, TAU, 20, Color(0.75, 1.0, 0.8), 2.0)
			for q in 4:
				var a: float = float(bm.spin) + q * TAU / 4.0
				var v := Vector2.from_angle(a)
				o.cv.draw_colored_polygon(PackedVector2Array([p + v * (R - 2.0) + v.orthogonal() * 4.0, p + v * (R + 6.0), p + v * (R - 2.0) - v.orthogonal() * 4.0]), Color(0.85, 1.0, 0.9))


# ---------------------------------------------------------------- trig.on_mate_attack（character.gd 出手时广播）

## 队友 m 普攻出手：本干员生效中的 trig.on_mate_attack 在她的出手点播 fx（scope 缺省 others）
static func el_mate_attack(o, m) -> void:
	if o.pos == Vector2.INF or m == o or m.pos == Vector2.INF:
		return
	for t in o._trigs():
		if str(t.get("_tag", "")) != "trig.on_mate_attack" or not cond_true(o, t.get("cond", _ED)):
			continue
		if not m in aura_members(o, str(t.get("scope", "others"))):
			continue
		var c: Vector2 = m.pos + Vector2(14.0 * float(m.face), -30.0)
		if t.has("fx"):
			fx_play(o, t.fx, c, 12.0)


# ---------------------------------------------------------------- 本段的校验

static func _el_st_common(b: Dictionary, p: String, ctx: Dictionary) -> void:
	if b.has("first_only") and not (b.first_only is bool):
		ctx.errs.append(p + ".first_only 只能是 true / false")
	_num(b, "cd", p, ctx, false, 0.0, 60.0)
	_num(b, "nearest_n", p, ctx, false, 1.0, 20.0)


static func _el_lunge_check(v, p: String, ctx: Dictionary) -> void:
	if not (v is Dictionary):
		ctx.errs.append(p + " 必须是对象 {min_d, t, cd, mult, r}")
		return
	for k in v:
		if not k in ["min_d", "t", "cd", "mult", "r", "fx", "_doc"]:
			ctx.errs.append("%s.%s：扑击只有 min_d / t / cd / mult / r / fx" % [p, k])
	_sm_exprs(v, p, ctx)
	_num(v, "min_d", p, ctx, true, 0.0, 400.0)
	_num(v, "t", p, ctx, true, 0.05, 1.0)
	_num(v, "cd", p, ctx, true, 0.0, 30.0)
	_num(v, "mult", p, ctx, true, 0.0, 10.0)
	_num(v, "r", p, ctx, true, 1.0, 300.0)
	if v.has("fx"):
		_fx(v.fx, p + ".fx", ctx, "shape.circle")


## _block 转来：本段的积木校验完返回 true
static func _el_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in EL_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {
		"st.stack": ["sustain"],
		"verb.buff_timed": ["skill", "instant"],
		"shape.boomerang": ["skill", "instant"],
		"verb.summon_cmd": ["skill", "instant"],
		"trig.on_mate_attack": ["trig"],
		"trig.on_mate_hook": ["trig"],
	}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"st.stack":
			if str(b.get("key", "")) == "":
				errs.append(p + " 缺 key（叠层的名字）")
			_num(b, "per", p, ctx, true, 0.0, 1.0)
			_num(b, "max", p, ctx, true, 1.0, 50.0)
			_num(b, "decay", p, ctx, true, 0.1, 10.0)
			var sl = b.get("src", [])
			if not (sl is Array) or sl.is_empty():
				errs.append(p + ".src 必须是非空数组（哪些伤害来源叠层）")
			else:
				for s in sl:
					if not ctx.srcs.has(str(s)):
						errs.append("%s.src「%s」没在 hit_sources 里登记" % [p, str(s)])
			if b.has("tex"):
				var tl = b.tex
				if not (tl is Array) or tl.is_empty() or tl.size() > 6 or tl.any(func(x): return not str(x).begins_with("proj_")):
					errs.append(p + ".tex 必须是 1–6 个 proj_* 帧条名的数组（按层数分档）")
			if b.has("full_fx") and not str(b.full_fx).begins_with("fx_"):
				errs.append(p + ".full_fx 必须是 fx_* 帧条名")
		"verb.buff_timed":
			var st := str(b.get("stat", ""))
			if not (st in LOCAL_STATS or st in OP_STATS):
				errs.append("%s.stat「%s」只能是 %s" % [p, st, " / ".join(LOCAL_STATS + OP_STATS)])
			if not str(b.get("op", "add")) in ["add", "mult"]:
				errs.append(p + ".op 只能是 add / mult")
			_num(b, "value", p, ctx, true, -1.0, 10.0)
			_num(b, "dur", p, ctx, true, 0.1, 60.0)
			if str(b.get("key", "")) == "":
				errs.append(p + " 缺 key（同 key 再触发只刷新时间）")
		"shape.boomerang":
			_num(b, "len", p, ctx, true, 20.0, 800.0)
			_num(b, "w", p, ctx, true, 4.0, 200.0)
			_num(b, "t_out", p, ctx, true, 0.05, 2.0)
			_num(b, "hold", p, ctx, false, 0.0, 2.0)
			_num(b, "t_back", p, ctx, true, 0.05, 2.0)
			_num(b, "mult_out", p, ctx, true, 0.0, 20.0)
			_num(b, "mult_back", p, ctx, true, 0.0, 20.0)
			_num(b, "kb_out", p, ctx, false, 0.0, 2000.0)
			_num(b, "scale", p, ctx, false, 0.2, 4.0)
			if b.has("lock") and not (b.lock is bool):
				errs.append(p + ".lock 只能是 true / false")
			for k in ["tex", "spark"]:
				if b.has(k) and not (str(b[k]).begins_with("proj_") or str(b[k]).begins_with("fx_")):
					errs.append("%s.%s 必须是帧条名（proj_* / fx_*）" % [p, k])
			_src(b, p, ctx, true)
		"verb.summon_cmd":
			var k := str(b.get("kind", ""))
			if not (ctx.summons is Dictionary and ctx.summons.has(k)):
				errs.append("%s.kind「%s」没在 blocks.summons 里定义" % [p, k])
			if not str(b.get("action", "")) in ["leap", "cast"]:
				errs.append(p + ".action 只能是 leap（跃回 to 身边）/ cast（原地施放，精英化第 5 批段）")
			if not str(b.get("to", "leader")) in ["leader", "self", "front"]:
				errs.append(p + ".to 只能是 leader / self / front")
			if str(b.get("to", "leader")) == "front":
				_num(b, "range", p, ctx, false, 40.0, 800.0)
				_num(b, "n", p, ctx, false, 1.0, 12.0)
				_num(b, "front_min", p, ctx, false, 20.0, 200.0)
				_num(b, "front_max", p, ctx, false, 20.0, 200.0)
				_num(b, "ring_clear", p, ctx, false, 0.0, 100.0)
			_num(b, "t", p, ctx, str(b.get("action", "")) == "leap", 0.05, 2.0)
			_num(b, "h", p, ctx, false, 0.0, 200.0)
			_num(b, "land_dx", p, ctx, false, 0.0, 200.0)
			_num(b, "land_dy", p, ctx, false, -100.0, 100.0)
			_list(b.get("then", []), p + ".then", "instant", ctx)
		"trig.on_mate_attack":
			var sc := str(b.get("scope", "others"))
			if not sc in ["others", "squad", "leader"]:
				errs.append(p + ".scope 只能是 others / squad / leader")
			if not b.has("fx"):
				errs.append(p + "：trig.on_mate_attack 只挂画面，要写 fx")
			if b.has("do") and not (b.do is Array and b.do.is_empty()):
				errs.append(p + "：trig.on_mate_attack 只挂画面，不写 do")
		"trig.on_mate_hook":   # 联动段（docs/123 §2.7「钩与锚」）：队友 shape.hookshot 拖回到位时执行 do（target = 落点）
			if b.has("op") and not (b.op is String):
				errs.append(p + ".op 须是干员 id 字符串")
			if b.has("knob") and not (b.knob is String and str(b.knob).contains("/")):
				errs.append(p + ".knob 须是 balance.json 的「段/键」路径")
			_num(b, "cd", p, ctx, false, 0.0, 60.0)
			_num(b, "range", p, ctx, false, 1.0, 2000.0)
			if not (b.get("do", null) is Array) or b.do.is_empty():
				errs.append(p + "：trig.on_mate_hook 要有 do（落点处执行的瞬时积木）")
			else:
				_list(b.do, p + ".do", "instant", ctx)
	return true
