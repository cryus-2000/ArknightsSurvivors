extends RefCounted
## 伊莎玛拉二阶段连段（docs/170，10-27；用户：打 Boss 要有图案弹幕、规律可学、节奏和压迫感，按本作题材表现，不照搬符卡）。
## 每幕 2 组，按现有幕制轮换；每组 ≤4 段的有限连段：段间收势，最后给破绽；眩晕 / 破绽 / 无敌 / 转幕 / 超时清掉未出的段（已飞出的弹保留）。
## 连段与 6 个新招式（合唱环颂、泪雨、抚愈之歌、网鸣、大群之声、歌声涟漪）为本作改编，不是原作技能名。
## 破网主轴：环颂 / 齐射 / 压境从连线海嗣发射，抚愈之歌在歌声结束时治疗仍连着的海嗣，泪雨从歌眼也落一颗。拆网 = 减弹。
## 状态全部在敌人字典 e 上，不用随机数（同 seed 可复现）。
const Bal = preload("res://scripts/core/balance.gd")
const Beam = preload("res://scripts/render/boss_beam.gd")

const COL := Color(0.3, 1.0, 0.65)
const NEW_MOVES := ["合唱环颂", "泪雨", "抚愈之歌", "网鸣", "大群之声", "歌声涟漪"]
## [幕][组]：name 只用于演练列表与测试（不出横幅），seq 为连段各段（撕咬按距离自动变横扫）
const CARDS := [
	[{"name": "合唱连段", "seq": ["合唱环颂", "合唱齐射", "歌声涟漪", "撕咬"]},
	 {"name": "锁定连段", "seq": ["三线扫射", "大群之声", "深海触腕"]}],
	[{"name": "泪雨连段", "seq": ["泪雨", "歌声涟漪", "泪落"]},
	 {"name": "抚愈连段", "seq": ["抚愈之歌", "合唱压境", "大群之歌"]}],
	[{"name": "网鸣连段", "seq": ["网鸣", "大群之声", "撕咬"]},
	 {"name": "终曲连段", "seq": ["合唱环颂", "大群之歌", "泪雨", "三线扫射"]}],
]
const OWN_CAP := 170   # 她同时在场的弹上限（boss_patterns 单体 160 / 全局 320 同量级）
const CARD_GUARD := 22.0   # 每组保护性上限

var g
var h   # ishar.gd（_ishar_phase2 / _fire_echoes）


func _init(game, host) -> void:
	g = game
	h = host


static func card_names() -> Array:
	var out: Array = []
	for act in CARDS:
		for c in act:
			out.append(c.name)
	return out


func act_of(e: Dictionary) -> int:
	return clampi(int(e.get("gates_passed", 0)), 0, 2)


## 每帧（变身完成后）。补充招式改由连段调度：压住 final_attacks 的独立轮换
func step(e: Dictionary, dir: Vector2, dist: float, ready: bool) -> void:
	e.final_next = INF
	_emit_step(e)
	_beam_fades(e)
	_zone_step(e)
	if e.get("card_live", false):
		if _broken(e):
			cancel(e)
			return
		var gap: float = 0.22 if act_of(e) == 2 else Bal.v("boss/ishar_combo_gap", 0.26)   # 10-28：一二幕 0.32 → 0.26，衔接更紧
		if not ready or _pending(e):
			e.card_next = maxf(float(e.card_next), g.t + gap)
			return
		if g.t < float(e.card_next):
			return
		var q: Array = e.card_q
		if q.is_empty():
			# 破绽不和密集弹幕重叠（协调人 10-27「给干员输出的机会」）：她自己的弹落到 20 枚以下再收招，最多多等 2.5 秒
			if _own_live(e) >= 20 and g.t < float(e.get("card_tail", INF)):
				if not e.has("card_tail") or float(e.card_tail) == INF:
					e.card_tail = g.t + 2.5
				return
			e.card_tail = INF
			_finish(e)
			return
		var mv: String = str(q.pop_front())
		var pause: float = play(e, mv, dir, dist)
		e.card_next = g.t + gap + pause
		return
	if not ready or g.t < float(e.get("ishar_next_at", 0.0)):
		return
	if h._fire_echoes(e):
		return
	# 潮涌迫近只在两组连段之间：她离得远时先冲到主控前
	var cdur: float = h._close_in(e, dir, dist, "ishar", "潮涌迫近", COL)
	if cdur >= 0.0:
		e.ishar_next_at = g.t + cdur + 0.6
		return
	var act: int = act_of(e)
	if int(e.get("card_act", -1)) != act:
		e.card_act = act
		e.card_k = 0
	var card: Dictionary = CARDS[act][int(e.card_k) % CARDS[act].size()]
	e.card_k = int(e.card_k) + 1
	start(e, card)


func start(e: Dictionary, card: Dictionary) -> void:
	e.card_live = true
	e.card_q = card.seq.duplicate()
	e.card_name = card.name
	e.card_no = card_names().find(card.name) + 1
	e.card_until = g.t + CARD_GUARD
	e.card_next = g.t + 0.45   # 起势：本体青光一涨，再出第一段
	g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.6, "life": 0.6, "max": 0.6, "col": COL, "enemy": true})
	Sfx.play("tentacle", -7.0, 0.7)


## 演练 / 预览：直接开一组（名字不对返回 false）
func force(e: Dictionary, name: String) -> bool:
	for act in CARDS:
		for c in act:
			if c.name == name:
				cancel(e)
				e.erase("break_t")
				e.break_t = 0.0
				start(e, c)
				e.card_next = g.t
				return true
	return false


func _broken(e: Dictionary) -> bool:
	return e.dead or e.get("invuln", false) or e.stun > 0.0 or float(e.get("break_t", 0.0)) > 0.0 \
		or g.t > float(e.get("card_until", INF)) or g.t < float(e.get("transform_until", 0.0))


## 她自己的、仍在读条的伤害预警或待发弹幕（泪眼周期共鸣不算，免得每 6 秒卡住连段）
func _own_live(e: Dictionary) -> int:
	var n := 0
	for b in g.ebullets:
		if b.life > 0.0 and b.get("source_id", -1) == e.id:
			n += 1
	return n


func _pending(e: Dictionary) -> bool:
	if not e.get("ishar_emits", []).is_empty():
		return true
	for w in g.warns:
		if is_same(w.owner, e) and not w.done and w.dmg > 0.0 and w.act != "ishar_echo":
			return true
	return false


func _finish(e: Dictionary) -> void:
	e.card_live = false
	# 破绽时长（10-28 测试台：破绽期输出只占 12%，目标 ≥35%）：一二幕 boss/ishar_break_t（3.0）、三幕 boss/ishar_break_t3（2.6）；破绽期网的减伤失效（ishar.taken_mult）
	var rec: float = Bal.v("boss/ishar_break_t3", 2.6) if act_of(e) == 2 else Bal.v("boss/ishar_break_t", 3.0)
	g.combat.start_break(e, rec)
	e.brk_label = "破绽"
	e.wind = maxf(e.wind, rec)
	e.ishar_next_at = g.t + rec + 0.3


## 打断：未出的段与待发弹清掉，已经飞出去的弹保留
func cancel(e: Dictionary) -> void:
	var was: bool = e.get("card_live", false)
	e.card_live = false
	e.card_q = []
	e.card_tail = INF
	e.ishar_emits = []
	if was:
		g.warns = g.warns.filter(func(w): return not is_same(w.owner, e) or w.done or w.act == "ishar_echo")
		e.ishar_next_at = maxf(float(e.get("ishar_next_at", 0.0)), g.t + 1.0)


## 转幕（combat.gate_pass → ishar.on_gate）：只清未出的段，下一组按新幕选；gate_pass 自带 0.8 秒不出招
func on_gate(e: Dictionary) -> void:
	cancel(e)
	e.card_act = -1


## 出一段；返回段后额外停顿（三幕分锁三线扫射之后的 2 秒）
func play(e: Dictionary, mv: String, dir: Vector2, dist: float) -> float:
	var i: int = h.MOVES.find(mv)
	if i >= 0:
		e.ishar_pause = 0.0
		h._ishar_phase2(e, dir, dist, i)
		return float(e.get("ishar_pause", 0.0))
	if g.bai.finals.NAMES.ishar.has(mv):
		g.bai.finals.force_move(e, mv, dir, dist)
		e.final_next = INF
		return 0.0
	match mv:
		"合唱环颂": _chorus_rings(e)
		"泪雨": _tear_rain(e)
		"抚愈之歌": _heal_song(e)
		"网鸣": _web_chime(e)
		"大群之声": _big_beam(e)
		"歌声涟漪": _song_zones(e)
		_: return 0.0
	e.move_name = mv
	e.move_t = g.t
	g.bai.claim_token(e, g.t + float(e.wind) + 0.6)
	return 0.0


## ---- 弹幕（ebullets：Boss 弹，专属色发光弹芯 + 暗描边由 world 统一画；enemies.json bcol_core / bcol_outline）
## 弹体分级：音弹 r6（中速）、大泪 r13（慢）、碎片 r5（快）；均为真实伤害

func _emit(e: Dictionary, at: float, d: Dictionary) -> void:
	d.at = at
	if not e.has("ishar_emits"):
		e.ishar_emits = []
	e.ishar_emits.append(d)


func _emit_step(e: Dictionary) -> void:
	var q: Array = e.get("ishar_emits", [])
	if q.is_empty():
		return
	var own := -1
	var keep: Array = []
	for d in q:
		if g.t < float(d.at):
			keep.append(d)
			continue
		var src = d.get("src")
		if src is Dictionary and src.get("dead", false):
			if d.get("b") is Dictionary:
				d.b.life = 0.0   # 沿线流动的歌声随节点一起断
			continue   # 发射源被击杀：这一发取消
		if own < 0:
			own = 0
			for b in g.ebullets:
				if b.life > 0.0 and b.get("source_id", -1) == e.id:
					own += 1
		match str(d.kind):
			"ring":
				# gap = 去掉的相邻弹位数（缺口中心在 gc）；hold > 0 = 先在原地排成圈停 hold 秒再一起射出；gap 0 = 整圈（a0 起算，旧写法）
				var p: Vector2 = src.pos if src is Dictionary else e.pos
				var n: int = int(d.n)
				var gap: int = int(d.get("gap", 0))
				var hold: float = float(d.get("hold", 0.0))
				var off: float = 0.5 if gap > 0 and gap % 2 == 0 else 0.0
				var c0: float = float(d.get("gc", d.get("a0", 0.0)))
				var held: Array = []
				for k in n:
					if gap > 0 and (k < ((gap + 1) >> 1) or k >= n - (gap >> 1)):
						continue
					var b = _shot_ref(e, own, p, c0 + TAU * (k + off) / float(n), float(d.get("spd", 95.0)), 6.0, float(d.get("mult", 0.28)), "ishar_note", 5.0 + hold)
					if b != null:
						own += 1
						if hold > 0.0:
							b.hold_v = b.vel
							b.vel = Vector2.ZERO
							held.append(b)
				if not held.is_empty():
					keep.append({"at": g.t + hold, "kind": "release", "bs": held})
			"release":
				for b in d.bs:
					if b.life > 0.0:
						b.vel = b.hold_v
			"drop":
				var p: Vector2 = src.pos if src is Dictionary else e.pos
				var b = _shot_ref(e, own, p, float(d.ang), 72.0, 13.0, 0.42, "ishar_tear", 7.0)
				if b != null:
					own += 1
					keep.append({"at": g.t + float(d.burst), "kind": "burst", "b": b})
			"burst":
				var b: Dictionary = d.b
				if b.life > 0.0:
					b.life = 0.0
					_grains(b.pos, 10, "bfx_burst", false)   # 泪碎：颗粒迸散（docs/136），不画实心环
					var a0: float = b.vel.angle() + PI / 6.0
					for k in 6:
						own += _shot(e, own, b.pos, a0 + TAU * k / 6.0, 165.0, 5.0, 0.2, "ishar_shard", 2.4)
			"pulse":
				# 歌声沿连线流向节点海嗣，到达时从节点向外散开
				var node: Dictionary = src
				var to: Vector2 = node.pos - e.pos
				var b = _shot_ref(e, own, e.pos, to.angle(), 150.0, 8.0, 0.25, "ishar_tear", to.length() / 150.0 + 0.2)
				if b != null:
					own += 1
					keep.append({"at": g.t + to.length() / 150.0, "kind": "node_burst", "src": node, "b": b, "a0": to.angle() + float(d.rot)})
			"node_burst":
				var b: Dictionary = d.b
				b.life = 0.0
				_grains(src.pos, 6, "bfx_flash", false)
				for k in 4:
					own += _shot(e, own, src.pos, float(d.a0) + (k - 1.5) * 0.5, 110.0, 6.0, 0.25, "ishar_note")
			"hold":
				# 大群之声的持续段：沿锁定线每 0.1 秒补画光束并判定（进来的人照样受伤，命中后有通用无敌帧）
				var w: Dictionary = d.w
				var dv := Vector2.from_angle(w.ang)
				g.fx.append({"kind": "bbeam", "a": w.pos, "b": w.pos + dv * w.len, "life": 0.14, "max": 0.14, "col": COL, "wid": w.wid, "enemy": true})
				var hd: Dictionary = w.duplicate()
				hd.dmg = float(w.dmg) * 0.5
				if g.invuln <= 0.0 and g.tele.hits_leader(hd):
					g.tele.warn_damage(hd)
				_grains(w.pos + dv * fmod(g.t * 900.0, w.len), 4, "bfx_flash", false)
				if d.get("last", false):
					_fade_fx(w)
			"arms":
				for k in int(d.n):
					own += _shot(e, own, e.pos, float(d.a0) + TAU * k / float(d.n), float(d.spd), float(d.r), 0.25,
						"ishar_tear" if float(d.r) > 7.0 else "ishar_note")
			"link":
				_grains(e.pos, 6, "mote_up", false)   # 歌声：本体身上持续升起的青色颗粒
				for sl in e.get("web", []):
					var o = sl.get("o")
					if o is Dictionary and not o.dead:
						g.fx.append({"kind": "tide_link", "a": e.pos, "b": o.pos, "life": 0.34, "max": 0.34, "col": COL, "enemy": true})
			"heal":
				for sl in e.get("web", []):
					var o = sl.get("o")
					if o is Dictionary and not o.dead and o.hp < o.maxhp:
						o.hp = o.maxhp
						g.vfx.add_text(o.pos + Vector2(0, -30), "抚愈", COL, 14)
						_grains(o.pos, 10, "mote_up", false)
	e.ishar_emits = keep


func _shot(e: Dictionary, own: int, p: Vector2, ang: float, spd: float, r: float, mult: float, kind: String, life := 6.5) -> int:
	return 0 if _shot_ref(e, own, p, ang, spd, r, mult, kind, life) == null else 1


func _shot_ref(e: Dictionary, own: int, p: Vector2, ang: float, spd: float, r: float, mult: float, kind: String, life := 6.5):
	if own >= OWN_CAP:
		return null
	var b := {"pos": p, "vel": Vector2.from_angle(ang) * spd, "dmg": e.dmg * mult * Bal.v("boss/ishar_shot_mult", 1.2), "r": r, "life": life,
		"slow": false, "frost": 0.0, "corrode": 0.0, "nerve": 0.0, "true": true, "kind": kind, "home": false, "boss": true,
		"atk": "法术", "hit_cap": e.get("hit_cap", 0.0), "source_id": e.id, "col": COL, "src_type": "ishar"}
	g.ebullets.append(b)
	return b


func _aim(p: Vector2) -> float:
	return (g.ppos - p).angle() if g.ppos.distance_to(p) > 1.0 else 0.0


## 合唱环颂：每个合唱源（≤3 只连线海嗣，网空时本体）0.8 秒蓄音后连发 3 圈慢速音弹（95px/s），各源错开 0.25 秒。缺口按幕递进（用户 10-28）：
##   一幕（教学）：12 位去 3 位的固定缺口，三圈都对准出招时主控的方向，站进缺口就过；
##   二幕：14 位去 3 位，缺口每圈转 0.55 弧度（相邻两个源方向相反），要跟着缺口绕；圈距 0.9 秒；
##   三幕：15 位去 2 位（缝更窄），每圈先在源周围排成圈停 0.6 秒再一起射出（停顿 = 看清缺口的时间窗），缺口每圈转 0.45 弧度；
##   二、三幕每第 3 次环颂的最后一圈是不留缺口的慢速整墙（20 枚、70px/s、单发伤害低），用冲刺穿过。击杀源取消它剩下的圈。
func _chorus_rings(e: Dictionary) -> void:
	var sources: Array = g.bai.finals.choir_sources(e)
	var solo: bool = sources.size() == 1 and is_same(sources[0], e)
	var act: int = act_of(e)
	var n: int = [12, 14, 15][act]
	var gap: int = [3, 3, 2][act]
	var spin: float = [0.0, 0.55, 0.45][act]
	var hold: float = 0.6 if act == 2 else 0.0
	var step_t: float = 1.0 if act == 0 else 0.9
	var waves: int = 2 if solo else 3
	e.chorus_k = int(e.get("chorus_k", 0)) + 1
	var wall: bool = act >= 1 and int(e.chorus_k) % 3 == 0
	for k in sources.size():
		var s: Dictionary = sources[k]
		g.fx.append({"kind": "ring", "pos": s.pos, "r": 30.0, "life": 0.8, "max": 0.8, "col": COL, "enemy": true})
		_grains(s.pos, 12, "mote_in", true)
		var gc: float = _aim(s.pos)
		var sgn: float = 1.0 if k % 2 == 0 else -1.0
		for w in waves:
			var d := {"kind": "ring", "src": null if is_same(s, e) else s, "n": n, "gap": gap, "gc": gc + sgn * spin * w, "hold": hold}
			if wall and w == waves - 1:
				d.merge({"n": 20, "gap": 0, "a0": gc, "spd": 70.0, "mult": 0.16, "hold": 0.0}, true)
			_emit(e, g.t + 0.8 + step_t * w + 0.25 * k, d)
	if wall:
		g.vfx.add_text(e.pos + Vector2(0, -70), "合唱成墙 · 冲刺穿过", COL, 16)
	var dur: float = 0.8 + step_t * (waves - 1) + 0.25 * (sources.size() - 1) + hold
	e.wind = maxf(e.wind, dur)
	e.cdt = maxf(e.cdt, dur)
	Sfx.play("tentacle", -8.0, 1.25)


## 泪雨：本体朝主控扇形落 5 颗大泪（二幕 6、三幕 7 颗，r13、72px/s），每颗 1.6 秒后碎成 6 枚快速小弹（165px/s）；
## 每个仍在的歌眼也朝主控落 1 颗。慢弹控走位，碎片考验离大泪的距离。
func _tear_rain(e: Dictionary) -> void:
	var n: int = [5, 6, 7][act_of(e)]   # 10-28：二幕 5 → 6
	var aim: float = _aim(e.pos)
	var spread := 1.3
	g.fx.append({"kind": "ring", "pos": e.pos, "r": 40.0, "life": 0.6, "max": 0.6, "col": COL, "enemy": true})
	_grains(e.pos, 14, "mote_in", true)
	for k in n:
		var a: float = aim + lerpf(-spread * 0.5, spread * 0.5, float(k) / (n - 1))
		_emit(e, g.t + 0.6 + 0.12 * k, {"kind": "drop", "src": null, "ang": a, "burst": 1.6 + 0.15 * k})
	var j := 0
	for o in e.get("eyes", []):
		if not o.dead:
			g.fx.append({"kind": "ring", "pos": o.pos, "r": 26.0, "life": 0.6, "max": 0.6, "col": COL, "enemy": true})
			_emit(e, g.t + 0.75 + 0.2 * j, {"kind": "drop", "src": o, "ang": _aim(o.pos), "burst": 1.8})
			j += 1
	var dur: float = 0.6 + 0.12 * (n - 1)
	e.wind = maxf(e.wind, dur)
	e.cdt = maxf(e.cdt, dur)
	Sfx.play("tentacle", -8.0, 0.85)


## 抚愈之歌（取材人形的治疗）：2.4 秒歌声，期间连线常亮，同时放四瓣慢速花形弹（二幕起五瓣；每 0.4 秒一层、每层转 0.26 弧度，85px/s）；
## 歌声结束时仍连着的海嗣回满生命。眩晕 / 破绽打断整首歌（治疗也取消）。
func _heal_song(e: Dictionary) -> void:
	var base: float = _aim(e.pos) + PI / 4.0
	for k in 8:
		_emit(e, g.t + 0.3 * k, {"kind": "link", "src": null})
	for k in 6:
		_emit(e, g.t + 0.3 + 0.4 * k, {"kind": "arms", "src": null, "n": 4 if act_of(e) == 0 else 5, "a0": base + 0.26 * k, "spd": 85.0, "r": 7.0})
	_emit(e, g.t + 2.4, {"kind": "heal", "src": null})
	e.wind = maxf(e.wind, 2.4)
	e.cdt = maxf(e.cdt, 2.4)
	g.vfx.add_text(e.pos + Vector2(0, -70), "歌声结束时治疗连线海嗣", COL, 16)


## 网鸣（取材「它为大群发声」：歌声经网传给每只连线海嗣）：每 1.1 秒一波，歌声团（r8、150px/s）沿每条连线流到节点，
## 到达后从节点向外散成 4 枚音弹扇（110px/s，间隔 0.5 弧度），每波扇面偏转 0.25 弧度，共三波。
## 击破节点海嗣：流向它的歌声当场消散、该节点不再散弹。网空时本体放两圈 12 枚（保底）。
func _web_chime(e: Dictionary) -> void:
	var nodes: Array = []
	for sl in e.get("web", []):
		var o = sl.get("o")
		if o is Dictionary and not o.dead:
			nodes.append(o)
	var waves := 3
	g.fx.append({"kind": "ring", "pos": e.pos, "r": 50.0, "life": 0.7, "max": 0.7, "col": COL, "enemy": true})
	_grains(e.pos, 14, "mote_in", true)
	if nodes.is_empty():
		for w in 2:
			_emit(e, g.t + 0.7 + 1.1 * w, {"kind": "ring", "src": null, "n": 10, "a0": _aim(e.pos) + PI / 12.0 * (w + 1)})
	for w in waves:
		for o in nodes:
			_emit(e, g.t + 0.7 + 1.1 * w, {"kind": "pulse", "src": o, "rot": 0.25 * w})
	var dur: float = 0.7 + 1.1 * (waves - 1)
	e.wind = maxf(e.wind, dur)
	e.cdt = maxf(e.cdt, dur)
	Sfx.play("tentacle", -8.0, 0.65)


## 颗粒（docs/136：共用 2 像素 CPU 池与 Boss 颗粒预算，低画质 / 关光学观感时不画）；inward = 从外圈流向点（蓄势），否则从点迸出
func _grains(p: Vector2, n: int, tmpl: String, inward: bool) -> void:
	if Cfg.quality == "low" or g is Dictionary:
		return
	var pool = Beam.grains(g)
	if pool == null:
		return
	n = Beam.take(g, n)
	for i in n:
		var d := Vector2.from_angle(TAU * i / maxf(1.0, n))
		pool.push(tmpl, p + d * 46.0 if inward else p, -d if inward else d, COL)


## 大群之声（取材「它为大群发声」，本作改编）：粗光束。1.8 秒预警（前 1.1 秒跟随主控，之后锁定 0.7 秒），
## 宽 92（半宽 46）、长 900；结算一次 e.dmg × 0.9，之后持续 1.0 秒，站在里面每次 × 0.45。锁定后侧移一个身位即可躲开。
func _big_beam(e: Dictionary) -> void:
	var a: float = _aim(e.pos)
	var w: Dictionary = h._warn(e, "line", 1.8, {"pos": e.pos, "ang": a, "len": 900.0, "wid": 46.0, "track": 1.1,
		"act": "ishar_line", "true": true, "name": "大群之声", "col": COL, "dmg": e.dmg * 0.9, "cancel_dead": true, "lock": true, "fade_delay": true})
	for k in 10:
		_emit(e, g.t + w.dur + 0.1 * (k + 1), {"kind": "hold", "src": null, "w": w, "last": k == 9})
	_grains(e.pos, 16, "mote_in", true)
	e.wind = maxf(e.wind, w.dur + 1.0)
	e.cdt = maxf(e.cdt, w.dur + 1.0)


## ---- 光束的开火与消散（用户 10-27：蓄力从细到粗、开火短闪、结束变细断成碎段散开，不硬切）
## 蓄力画在 render/ishar_tell_draw（读条进度）；这里在结算那一帧补一条 0.35 秒的消散记录 + 沿线颗粒。只写画面字典，不影响判定。
static func is_beam(w: Dictionary) -> bool:
	var act: String = str(w.get("act", ""))
	return w.get("shape", "") == "line" and (act in ["ishar_line", "ishar_echo"] or (act == "final_attack" and str(w.get("skin", "")) == "choir"))


func _beam_fades(e: Dictionary) -> void:
	for w in g.warns:
		if w.done and not w.get("faded", false) and is_same(w.owner, e) and is_beam(w) and not w.get("fade_delay", false):
			w.faded = true
			_fade_fx(w)


func _fade_fx(w: Dictionary) -> void:
	var dv := Vector2.from_angle(w.ang)
	g.fx.append({"kind": "ishar_beam_fade", "a": w.pos, "b": w.pos + dv * float(w.len), "wid": float(w.wid), "life": 0.35, "max": 0.35, "enemy": true})
	for k in 8:
		_grains(w.pos + dv * float(w.len) * (k + 0.5) / 8.0, 2, "bfx_dust", false)


## 歌声涟漪（非弹幕，取材她的歌声笼罩战场）：主控脚下、移动方向前方 200、再前方偏侧各一处 r105 的涟漪区，1.3 秒预警后
## 结算一次 e.dmg × 0.35，之后留 boss/ishar_zone_linger（4）秒：站在里面每 0.5 秒 e.dmg × boss/ishar_zone_tick（0.16） 并减速（移速 × 0.75）。逼主控换方向走，不追人。
func _song_zones(e: Dictionary) -> void:
	var p0: Vector2 = g.combat.arena_clamp(g.ppos, 90.0)
	var fwd: Vector2 = g.pvel.normalized() if g.pvel.length() > 20.0 else (g.ppos - e.pos).normalized().orthogonal()
	var spots: Array = [p0, p0 + fwd * 200.0, p0 + fwd.rotated(0.9) * 330.0]
	for k in spots.size():
		var p: Vector2 = g.combat.arena_clamp(spots[k], 90.0)
		var w: Dictionary = h._warn(e, "circle", 1.3 + 0.25 * k, {"pos": p, "r": 105.0, "act": "ishar_strike", "true": true,
			"name": "歌声涟漪" if k == 0 else "", "col": COL, "dmg": e.dmg * 0.35, "cancel_dead": true, "lock": k == 0})
		if not e.has("ishar_zones"):
			e.ishar_zones = []
		e.ishar_zones.append({"pos": p, "r": 105.0, "born": g.t + w.dur, "until": g.t + w.dur + Bal.v("boss/ishar_zone_linger", 4.0), "next": g.t + w.dur + 0.5, "w": w})
	e.wind = maxf(e.wind, 1.8)
	e.cdt = maxf(e.cdt, 1.8)


func _zone_step(e: Dictionary) -> void:
	var zs: Array = e.get("ishar_zones", [])
	if zs.is_empty():
		return
	var keep: Array = []
	for z in zs:
		if g.t >= float(z.until) or e.dead:
			continue
		keep.append(z)
		if g.t < float(z.born) or g.t < float(z.next):
			continue
		z.next = float(z.next) + 0.5
		if g.combat.ground_d(g.ppos, z.pos) < float(z.r):
			g.combat.slow_leader("ishar_song", 0.6, 0.75)
			if g.invuln <= 0.0:
				var hd: Dictionary = z.w.duplicate()
				hd.dmg = e.dmg * Bal.v("boss/ishar_zone_tick", 0.16)
				g.tele.warn_damage(hd)
	e.ishar_zones = keep
