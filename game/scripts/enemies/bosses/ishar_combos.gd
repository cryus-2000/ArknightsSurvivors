extends RefCounted
## 伊莎玛拉二阶段连段（docs/170，10-27；用户：打 Boss 要有图案弹幕、规律可学、节奏和压迫感，按本作题材表现，不照搬符卡）。
## 每幕 2 组，按现有幕制轮换；每组 ≤4 段的有限连段：段间收势，最后给破绽；眩晕 / 破绽 / 无敌 / 转幕 / 超时清掉未出的段（已飞出的弹保留）。
## 连段与 6 个新招式（合唱环颂、泪雨、抚愈之歌、网鸣、大群之声、歌声涟漪）为本作改编，不是原作技能名。
## 破网主轴：环颂 / 齐射 / 压境从连线海嗣发射，抚愈之歌在歌声结束时治疗仍连着的海嗣，泪雨从歌眼也落一颗。拆网 = 减弹。
## 状态全部在敌人字典 e 上，不用随机数（同 seed 可复现）。
const Bal = preload("res://scripts/core/balance.gd")
const Beam = preload("res://scripts/render/boss_beam.gd")

const COL := Color(0.3, 1.0, 0.65)
const NEW_MOVES := ["合唱环颂", "泪雨", "抚愈之歌", "网鸣", "大群之声", "歌声涟漪", "潮涡", "侵蚀之泪", "大群之声·双束", "潮涌突进", "合围之歌", "三重齐击", "重生之歌"]
## [幕][组]：name 只用于演练列表与测试（不出横幅），seq 为连段各段（撕咬按距离自动变横扫）
## 10-28 用户「不同阶段攻击方式差距不大」→ 每幕一个躲法主题，招式不跨幕复用（docs/170b §2）：
##   一幕「读线」：她站定唱歌不追人，只出预警线 / 地带（激光、追扫、涟漪、触腕），不出成片弹幕；
##   二幕「躲落、躲旋」：她在场上潮涌突进，落点就是下一招的发射点；全是弹幕，没有光束；
##   三幕「被围住」：她沉到场地中央不再移动，场边一圈歌声慢慢收拢（_fence），出追踪 / 合拢 / 链式 / 停顿再射。
const CARDS := [
	[{"name": "歌声连段", "seq": ["歌声涟漪", "合唱齐射", "三重齐击"]},   # 10-31 用户选 A：深海触腕不符合设定，换成原作「同时攻击 3 个目标」
	 {"name": "锁定连段", "seq": ["三线扫射", "大群之声", "歌声涟漪"]}],
	[{"name": "泪雨连段", "seq": ["潮涌突进", "泪雨", "潮涡", "撕咬"]},
	 {"name": "抚愈连段", "seq": ["潮涌突进", "抚愈之歌", "泪落", "大群之歌"]}],
	[{"name": "网鸣连段", "seq": ["网鸣", "重生之歌", "侵蚀之泪"]},   # 10-31 用户选 C：取材原作变身形态被击败后的重生
	 {"name": "终曲连段", "seq": ["合唱环颂", "大群之声·双束", "侵蚀之泪"]}],
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


## 每幕主色（docs/170 §15）：10-28 起只用于场地底色（act_mood）；弹芯走专属色（enemies.json ishar.bcol_core），见 act_col。
## 一幕「余韵」：近白的浅青（人形歌声，稀疏优雅）；二幕「海嗣化」：深海青绿（压迫）；三幕「腐化之心」：腐红（整场变色）
const ACT_COL := [Color(0.8, 1.0, 0.94), Color(0.36, 0.95, 0.72), Color(1.0, 0.42, 0.55)]


## 10-28 用户「弹幕颜色统一，更有记忆点」：弹、光圈、冲刺拖尾、围拢圈一律用她的专属色（enemies.json ishar.bcol）；
## 每幕主色只留给场地底色（act_mood：二幕潮纹、三幕腐红），各幕靠弹形（音符 / 泪 / 碎片）和招式区分
static func act_col(_e: Dictionary) -> Color:
	return COL


static func act_mood(e: Dictionary) -> Color:
	return ACT_COL[clampi(int(e.get("gates_passed", 0)), 0, 2)]


## 每帧（变身完成后）。补充招式改由连段调度：压住 final_attacks 的独立轮换
func step(e: Dictionary, dir: Vector2, dist: float, ready: bool) -> void:
	e.final_next = INF
	_emit_step(e)
	_beam_fades(e)
	_zone_step(e)
	_sweep_step(e)
	_act_step(e)
	if e.get("card_live", false):
		if _broken(e):
			cancel(e)
			return
		var gap: float = [Bal.v("boss/ishar_combo_gap", 0.26), 0.24, 0.2][act_of(e)] * Bal.v("boss/tempo_k_ishar", 0.75)   # 每幕节奏（docs/170 §15）：一幕留呼吸、二幕压迫、三幕最紧
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
	# 潮涌迫近只在二幕两组连段之间（一幕站定唱歌、三幕钉在中央）
	var cdur: float = h._close_in(e, dir, dist, "ishar", "潮涌迫近", COL) if act_of(e) <= 1 else -1.0
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
	if card.name == "网鸣连段" and Bal.v("boss/ishar_inward_on", 1.0) > 0.0:
		e.card_q.insert(1, "合围之歌")   # 10-29 用户「三幕攻击方式偏少」：围拢圈本身也开口唱
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
	if not e.get("ishar_emits", []).is_empty() or not e.get("ishar_sweep", {}).is_empty() or not e.get("ishar_sweep2", {}).is_empty():
		return true
	for w in g.warns:
		if is_same(w.owner, e) and not w.done and w.dmg > 0.0 and w.act != "ishar_echo":
			return true
	return false


func _finish(e: Dictionary) -> void:
	e.card_live = false
	# 破绽时长（10-28 测试台：破绽期输出只占 12%，目标 ≥35%）：一二幕 boss/ishar_break_t（3.0）、三幕 boss/ishar_break_t3（2.6）；破绽期网的减伤失效（ishar.taken_mult）
	var rec: float = Bal.v("boss/ishar_break_t3", 4.8) if act_of(e) == 2 else Bal.v("boss/ishar_break_t", 6.0)
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
	_sweep_end(e)
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
	_cur_mv = mv
	match mv:
		"合唱环颂": _chorus_rings(e)
		"泪雨": _tear_rain(e)
		"抚愈之歌": _heal_song(e)
		"网鸣": _web_chime(e)
		"大群之声": _big_beam(e)
		"潮涡": _vortex(e)
		"侵蚀之泪": _seeking_tears(e)
		"大群之声·双束": _twin_beam(e)
		"潮涌突进": _surge(e)
		"三重齐击": _triple_strike(e)
		"重生之歌": _rebirth_song(e)
		"合围之歌": _inward_song(e)
		"歌声涟漪": _song_zones(e)
		_: return 0.0
	e.move_name = mv
	e.move_t = g.t
	g.bai.claim_token(e, g.t + float(e.wind) + 0.6)
	return 0.0


## ---- 弹幕（ebullets：Boss 弹，专属色发光弹芯 + 暗描边由 world 统一画；enemies.json bcol_core / bcol_outline）
## 弹体分级：音弹 r6（中速）、大泪 r13（慢）、碎片 r5（快）；均为真实伤害

## 按招式分工（10-29 docs/201 §8）：密度招 泪雨 / 合唱环颂 发数再 × ishar_dense_k；快节奏招 潮涡 / 侵蚀之泪 排程延迟再 × ishar_fast_k；其余当喘息段
var _cur_mv := ""


func _emit(e: Dictionary, at: float, d: Dictionary) -> void:
	if _cur_mv in ["泪雨", "合唱环颂"] and d.has("n"):
		var dk: float = Bal.v("boss/ishar_dense_k", 1.0)
		d.n = maxi(1, int(round(float(d.n) * dk)))
		if d.has("gap"):
			d.gap = int(round(float(d.gap) * dk))
	if _cur_mv in ["潮涡", "侵蚀之泪"]:
		at = g.t + maxf(0.0, at - g.t) * Bal.v("boss/ishar_fast_k", 1.0)
	# 10-29 docs/201 §7：发数 × boss/count_k_ishar（缺口格数同比放大，缺口角度不变），排程延迟 × boss/tempo_k_ishar
	var ck: float = Bal.v("boss/count_k_ishar", 1.4)
	if d.has("n") and ck != 1.0:
		d.n = maxi(1, int(round(float(d.n) * ck)))
		if d.has("gap"):
			d.gap = int(round(float(d.gap) * ck))
	d.at = g.t + maxf(0.0, at - g.t) * Bal.v("boss/tempo_k_ishar", 0.75)
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
					var b = _shot_ref(e, own, p, c0 + TAU * (k + off) / float(n), float(d.get("spd", 95.0)), 6.0, float(d.get("mult", 0.28)), ["ishar_note", "ishar_tear", "ishar_shard"][act_of(e)], 5.0 + hold)
					if b != null:
						own += 1
						if hold > 0.0:
							b.hold_v = b.vel
							b.vel = Vector2.ZERO
							held.append(b)
				if not held.is_empty():
					keep.append({"at": g.t + hold, "kind": "release", "bs": held})
			"inring":
				# 从围拢圈上排一圈音弹，停 hold 秒（看清缺口）后一起向场心收拢；缺口中心 gc
				var c: Vector2 = d.c
				var R: float = float(d.R)
				var n: int = int(d.n)
				var gap: int = int(d.gap)
				var held: Array = []
				for k in n:
					if k < ((gap + 1) >> 1) or k >= n - (gap >> 1):
						continue
					var a: float = float(d.gc) + TAU * (k + (0.5 if gap % 2 == 0 else 0.0)) / float(n)
					var b = _shot_ref(e, own, c + Vector2.from_angle(a) * R, a + PI, float(d.spd), 6.0, 0.26, "ishar_shard", float(d.hold) + (R - 70.0) / float(d.spd))
					if b != null:
						own += 1
						b.hold_v = b.vel
						b.vel = Vector2.ZERO
						held.append(b)
				if not held.is_empty():
					keep.append({"at": g.t + float(d.hold), "kind": "release", "bs": held})
					_grains(c + Vector2.from_angle(float(d.gc)) * R, 10, "bfx_flash", false)
			"rebirth_pulse":
				if g.t < float(e.get("rebirth_until", 0.0)):
					g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.0, "life": 0.5, "max": 0.5, "col": COL, "enemy": true})
					_grains(e.pos, 8, "mote_up", false)
			"release":
				for b in d.bs:
					if b.life > 0.0:
						b.vel = b.hold_v * float(b.get("spd_k", 1.0))   # 停住时记的是原速；弹速统一倍率（shot_pool._final_speed，docs/201）
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
			"dash":
				_dash_start(e, d.to, d.get("w"), 0.3)
			"sweep":
				_sweep_start(e, d.w, str(d.get("key", "ishar_sweep")), float(d.get("aim_off", 0.0)))
			"spiral":
				for k in int(d.arms):
					own += _shot(e, own, e.pos, float(d.a) + TAU * k / float(d.arms), 105.0, 6.0, 0.25, "ishar_tear", 5.5)
			"seek":
				var b = _shot_ref(e, own, e.pos + Vector2.from_angle(float(d.a)) * 40.0, float(d.a), 85.0, 9.0, 0.4, "ishar_tear", 7.0)
				if b != null:
					own += 1
					b.home = true
					keep.append({"at": g.t + Bal.v("boss/ishar_seek_t", 2.0), "kind": "unseek", "b": b})
			"unseek":
				d.b.home = false   # 追 2 秒后改走直线：急停 / 绕圈就能甩开
			"hold":
				# （旧）定向持续段：沿锁定线每 0.1 秒补画光束并判定；10-28 起大群之声改追扫，不再使用
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
	var b := {"pos": p, "vel": Vector2.from_angle(ang) * spd, "dmg": e.dmg * mult * Bal.v("boss/ishar_shot_mult", 1.4), "r": r, "life": life,
		"slow": false, "frost": 0.0, "corrode": Bal.v("boss/ishar_corrode", 1.0), "nerve": 0.0, "true": true, "kind": kind, "home": false, "boss": true,
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
	var n: int = [12, 14, 12][act]
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
		if o is Dictionary and not o.dead and nodes.size() < 6:
			nodes.append(o)   # 最多 6 个发声节点（三幕网上限 10，全发会到 120+ 枚）
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
	# 蓄力 1.6 秒（前 1.2 秒跟着队长转，读条画法同其他光束）；act ishar_sweep：预警结算本身不出伤害，由 _sweep_start 接手
	var w: Dictionary = h._warn(e, "line", 1.6, {"pos": e.pos, "ang": a, "len": 900.0, "wid": 46.0, "track": 1.2, "follow": true,
		"act": "ishar_sweep", "true": true, "name": "大群之声", "col": COL, "dmg": e.dmg * 0.9, "cancel_dead": true, "lock": true, "fade_delay": true})
	_emit(e, g.t + w.dur, {"kind": "sweep", "src": null, "w": w})
	_grains(e.pos, 16, "mote_in", true)
	var t: float = w.dur + Bal.v("boss/ishar_sweep_t", 2.4)
	e.wind = maxf(e.wind, t)
	e.cdt = maxf(e.cdt, t)


## ---- 大群之声 · 追扫（用户 10-28「大激光改成追着玩家扫射」）：光束状态记在 e.ishar_sweep，每帧连续画同一条（不再每 0.1 秒新建光束特效，
## 那会让激光画法每次从起点重新伸出、宽度从头走 = 10 Hz 频闪）。转向有惯性：角速度朝「对准队长」加速，上限 boss/ishar_sweep_max（0.5 rad/s），
## 角加速度 boss/ishar_sweep_acc（1.4 rad/s²）；队长绕她跑（距离 250 时约 0.5 rad/s 以上）就能甩开，冲刺穿过也行。
## 持续 boss/ishar_sweep_t（2.4）秒，每 0.15 秒判一次 e.dmg × 0.35（命中后有通用无敌帧）；结束 / 被打断都走消散。
const SWEEPS := ["ishar_sweep", "ishar_sweep2"]


func _sweep_start(e: Dictionary, w: Dictionary, key := "ishar_sweep", aim_off := 0.0) -> void:
	e[key] = {"pos": e.pos, "ang": float(w.ang), "av": 0.0, "len": float(w.len), "wid": float(w.wid), "t0": g.t,
		"t1": g.t + Bal.v("boss/ishar_sweep_t", 2.4), "next": g.t, "w": w, "off": aim_off}
	Sfx.play_cue("beam", "ishar", "hit")
	g.vfx.shake_screen(0.3)
	_grains(e.pos, 12, "bfx_flash", false)


func _sweep_step(e: Dictionary) -> void:
	for key in SWEEPS:
		_sweep_one(e, key)


func _sweep_one(e: Dictionary, key: String) -> void:
	var s: Dictionary = e.get(key, {})
	if s.is_empty():
		return
	if e.dead or g.t >= float(s.t1):
		_sweep_end(e, key)
		return
	var dt: float = clampf(g.t - float(s.get("last", g.t)), 0.0, 0.1)
	s.last = g.t
	s.pos = e.pos
	var want: float = angle_difference(float(s.ang), (g.ppos + Vector2(0, -14) - e.pos).angle() + float(s.get("off", 0.0)))
	var vmax: float = Bal.v("boss/ishar_sweep_max", 0.5)
	var tgt_av: float = clampf(want * 2.0, -vmax, vmax)
	s.av = move_toward(float(s.av), tgt_av, Bal.v("boss/ishar_sweep_acc", 1.4) * dt)
	s.ang = float(s.ang) + float(s.av) * dt
	if g.t >= float(s.next):
		s.next = float(s.next) + 0.15
		var hd: Dictionary = s.w.duplicate()
		hd.act = "ishar_line"
		hd.pos = e.pos
		hd.ang = s.ang
		hd.dmg = e.dmg * 0.35
		if g.invuln <= 0.0 and g.tele.hits_leader(hd):
			g.tele.warn_damage(hd)


func _sweep_end(e: Dictionary, key := "") -> void:
	for k in (SWEEPS if key == "" else [key]):
		var s: Dictionary = e.get(k, {})
		if s.is_empty():
			continue
		_fade_fx({"pos": e.pos, "ang": float(s.ang), "len": float(s.len), "wid": float(s.wid)})
		e[k] = {}


## ---- 光束的开火与消散（用户 10-27：蓄力从细到粗、开火短闪、结束变细断成碎段散开，不硬切）
## 蓄力画在 render/ishar_tell_draw（读条进度）；这里在结算那一帧补一条 0.35 秒的消散记录 + 沿线颗粒。只写画面字典，不影响判定。
static func is_beam(w: Dictionary) -> bool:
	var act: String = str(w.get("act", ""))
	return w.get("shape", "") == "line" and (act in ["ishar_line", "ishar_echo", "ishar_sweep"] or (act == "final_attack" and str(w.get("skin", "")) == "choir"))


func _beam_fades(e: Dictionary) -> void:
	for w in g.warns:
		if w.done and not w.get("faded", false) and is_same(w.owner, e) and is_beam(w) and not w.get("fade_delay", false):
			w.faded = true
			_fade_fx(w)


func _fade_fx(w: Dictionary) -> void:
	var dv := Vector2.from_angle(w.ang)
	var hold: float = 0.0 if w.has("t") == false else 0.3   # 预警结算的光束：先稳定亮 0.3 秒再消散；追扫收尾直接消散
	g.fx.append({"kind": "ishar_beam_fade", "a": w.pos, "b": w.pos + dv * float(w.len), "wid": float(w.wid), "life": 0.35 + hold, "max": 0.35 + hold, "hold": hold, "enemy": true})
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
		e.ishar_zones.append({"pos": p, "r": 105.0, "born": g.t + w.dur, "until": g.t + w.dur + Bal.v("boss/ishar_zone_linger", 6.0), "next": g.t + w.dur + 0.5, "w": w})
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
		if g.t >= float(z.born) and g.combat.ground_d(g.ppos, z.pos) < float(z.r):
			# 歌声侵蚀（10-28 协调人：「歌声治愈大群、侵蚀对手」）：站在地带内受治疗降低，离开即恢复（combat.song_heal_mult）
			if float(e.get("song_cut_until", 0.0)) < g.t and g.t >= float(e.get("song_tip_next", 0.0)):
				e.song_tip_next = g.t + 3.0
				g.vfx.add_text(g.ppos + Vector2(0, -80), "歌声侵蚀 · 受治疗 −%d%%" % roundi(100.0 * Bal.v("boss/ishar_song_heal_cut", 0.7)), Color(0.86, 0.26, 0.42), 15)
			e.song_cut_until = g.t + 0.1
		if g.t < float(z.born) or g.t < float(z.next):
			continue
		z.next = float(z.next) + 0.5
		if g.combat.ground_d(g.ppos, z.pos) < float(z.r):
			g.combat.slow_leader("ishar_song", 0.6, 0.75)
			if g.invuln <= 0.0:
				var hd: Dictionary = z.w.duplicate()
				hd.dmg = e.dmg * Bal.v("boss/ishar_zone_tick", 0.3)
				g.tele.warn_damage(hd)
	e.ishar_zones = keep


## ---- 三幕方案新招（docs/170b，10-28 用户「每幕招式和弹幕要真的不同」）

## 潮涡（二幕，本作自拟）：两臂螺旋从她身上转出（每 0.12 秒一对、105px/s），前 1.5 秒顺时针转、之后反向 1.5 秒；读出转向才能穿过臂间
func _vortex(e: Dictionary) -> void:
	var a0: float = _aim(e.pos) + PI * 0.5
	var w0: float = Bal.v("boss/ishar_vortex_spin", 1.8)
	var a: float = a0
	var n: int = 25
	for k in n:
		var t: float = 0.5 + 0.12 * k
		_emit(e, g.t + t, {"kind": "spiral", "src": null, "a": a, "arms": 2})
		a += (w0 if k < n / 2 else -w0) * 0.12
	g.fx.append({"kind": "ring", "pos": e.pos, "r": 46.0, "life": 0.5, "max": 0.5, "col": act_col(e), "enemy": true})
	_grains(e.pos, 14, "mote_in", true)
	var dur: float = 0.5 + 0.12 * (n - 1)
	e.wind = maxf(e.wind, dur)
	e.cdt = maxf(e.cdt, dur)
	Sfx.play("tentacle", -8.0, 0.75)


## 侵蚀之泪（三幕，本作自拟）：身边依次放出 5 颗慢速泪球（r9、85px/s），各追队长 boss/ishar_seek_t（2）秒（转向迟缓）后改走直线；绕圈或急停甩开
func _seeking_tears(e: Dictionary) -> void:
	var a0: float = _aim(e.pos)
	for k in 5:
		_emit(e, g.t + 0.4 + 0.25 * k, {"kind": "seek", "src": null, "a": a0 + (k - 2) * 0.7})
	g.vfx.add_text(e.pos + Vector2(0, -70), "侵蚀之泪 · 绕开它", act_col(e), 15)
	_grains(e.pos, 14, "mote_in", true)
	var dur: float = 0.4 + 0.25 * 4 + 1.0
	e.wind = maxf(e.wind, dur)
	e.cdt = maxf(e.cdt, dur)
	Sfx.play("tentacle", -8.0, 0.6)


## 合围之歌（三幕，本作自拟；开关 boss/ishar_inward_on）：场边的歌声围拢圈本身开口——沿圈排出一圈碎片音弹（36 位去 5 位），
## 先停 0.8 秒亮出缺口，再一起向场心收拢（80px/s，到她身边 70 像素消散）。共三圈、每圈相隔 1.4 秒，缺口每圈绕场心转 0.6 弧度（方向随出招次数交替），
## 第一圈缺口对准出招时的队长。躲法：贴着圈去找缺口、跟着缺口绕，或冲刺穿过；圈越收越密，越晚躲越难。没有围拢圈（不在三幕）就不出
func _inward_song(e: Dictionary) -> void:
	var f: Dictionary = e.get("ishar_fence", {})
	if f.is_empty():
		return
	var c: Vector2 = f.c
	var R: float = _fence_r(e) - 8.0
	var gc: float = (g.ppos - c).angle() if g.ppos.distance_to(c) > 1.0 else 0.0
	e.inward_k = int(e.get("inward_k", 0)) + 1
	var sgn: float = 1.0 if int(e.inward_k) % 2 == 1 else -1.0
	var waves := 3
	for w in waves:
		_emit(e, g.t + 0.5 + 1.4 * w, {"kind": "inring", "src": null, "c": c, "R": R, "n": 36, "gap": 5,
			"gc": gc + sgn * 0.6 * w, "spd": Bal.v("boss/ishar_inward_spd", 80.0), "hold": 0.8})
	g.fx.append({"kind": "ring", "pos": c, "r": R, "life": 0.7, "max": 0.7, "col": COL, "enemy": true})
	g.vfx.add_text(e.pos + Vector2(0, -70), "合围之歌 · 找缺口", COL, 15)
	Sfx.play("tentacle", -8.0, 0.55)
	var dur: float = 0.5 + 1.4 * (waves - 1) + 0.8 + 1.0
	e.wind = maxf(e.wind, dur)
	e.cdt = maxf(e.cdt, dur)


## 三重齐击（一幕，取材原作变身形态「同时攻击 3 个目标，造成真实伤害」，本作改编）：三处 r boss/ishar_triple_r（70）的落点同时预警 1.1 秒、同时结算，
## 各 e.dmg × 0.7 真伤：队长当前位置、沿移动方向 150 / 300 像素处（站着不动时改为身体两侧 150）。读法：看清三点后往没有圈的方向侧移
func _triple_strike(e: Dictionary) -> void:
	var mv: Vector2 = g.pvel.normalized() if g.pvel.length() > 20.0 else Vector2.ZERO
	var r: float = Bal.v("boss/ishar_triple_r", 70.0)
	var pts: Array = [g.ppos]
	if mv == Vector2.ZERO:
		var side: Vector2 = (g.ppos - e.pos).normalized().orthogonal() if g.ppos.distance_to(e.pos) > 1.0 else Vector2.RIGHT
		pts.append_array([g.ppos + side * 150.0, g.ppos - side * 150.0])
	else:
		pts.append_array([g.ppos + mv * 150.0, g.ppos + mv * 300.0])
	for k in 3:
		h._warn(e, "circle", 1.1, {"pos": g.combat.arena_clamp(pts[k], 60.0), "r": r, "act": "ishar_strike", "true": true, "seq_no": k + 1,
			"name": "三重齐击" if k == 0 else "", "col": COL, "dmg": e.dmg * 0.7, "cancel_dead": true, "lock": k == 0})
	_grains(e.pos, 12, "mote_in", true)
	e.wind = maxf(e.wind, 1.3)
	e.cdt = maxf(e.cdt, 1.3)
	Sfx.play("tentacle", -8.0, 1.1)


## 重生之歌（三幕，取材原作变身形态被击败后原地重生 5 秒，本作改编）：她 boss/ishar_rebirth_t（3）秒内不受伤害（e.rebirth_until，ishar.block_damage），
## 每只连线海嗣每 0.8 秒放一圈 8 枚音弹（共三圈，源被击杀就停）；网拆空（web_n = 0）当场结束。打她无效，拆网是唯一的应对
func _rebirth_song(e: Dictionary) -> void:
	var t: float = Bal.v("boss/ishar_rebirth_t", 3.0)
	e.rebirth_until = g.t + t
	var srcs: Array = []
	for sl in e.get("web", []):
		var o = sl.get("o")
		if o is Dictionary and not o.dead:
			srcs.append(o)
	for w in 3:
		for k in srcs.size():
			_emit(e, g.t + 0.4 + 0.8 * w + 0.05 * k, {"kind": "ring", "src": srcs[k], "n": 8, "a0": 0.39 * w + 0.2 * k, "spd": 90.0, "mult": 0.22})
		_emit(e, g.t + 0.4 + 0.8 * w, {"kind": "rebirth_pulse", "src": null})
	if srcs.is_empty():
		_emit(e, g.t + 0.4, {"kind": "ring", "src": null, "n": 12, "a0": 0.0, "spd": 90.0, "mult": 0.22})
	g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.4, "life": 0.8, "max": 0.8, "col": COL, "enemy": true})
	g.vfx.add_text(e.pos + Vector2(0, -80), "重生之歌 · 拆网打断", COL, 16)
	_grains(e.pos, 18, "mote_up", false)
	Sfx.play("tentacle", -6.0, 0.5)
	e.wind = maxf(e.wind, t)
	e.cdt = maxf(e.cdt, t)


## 大群之声·双束（三幕终曲）：两束较细的追扫（宽 64）从队长两侧 ±1.0 弧度起，各自追向「队长方向 ±0.32」，向你合拢后在两侧掠过，中间留一条可走的缝
func _twin_beam(e: Dictionary) -> void:
	var a: float = _aim(e.pos)
	var off: float = Bal.v("boss/ishar_twin_gap", 0.32)
	for k in 2:
		var sg: float = -1.0 if k == 0 else 1.0
		var w: Dictionary = h._warn(e, "line", 1.6, {"pos": e.pos, "ang": a + sg * 1.0, "len": 900.0, "wid": 32.0, "track": 0.0, "follow": true,
			"act": "ishar_sweep", "true": true, "name": "大群之声·双束" if k == 0 else "", "col": COL, "dmg": e.dmg * 0.9, "cancel_dead": true, "lock": k == 0, "fade_delay": true})
		_emit(e, g.t + w.dur, {"kind": "sweep", "src": null, "w": w, "key": SWEEPS[k], "aim_off": sg * off})
	_grains(e.pos, 16, "mote_in", true)
	var t: float = 1.6 + Bal.v("boss/ishar_sweep_t", 2.4)
	e.wind = maxf(e.wind, t)
	e.cdt = maxf(e.cdt, t)


## ---- 每幕的走位（docs/170b §2）
## 一幕：移速 0（站定唱歌）；二幕：移速照旧并有潮涌突进；三幕：开幕时 0.8 秒滑到场地中央，之后移速 0，场边歌声围拢开始收。
func _act_step(e: Dictionary) -> void:
	if not e.has("spd_base"):
		e.spd_base = e.spd
	var act: int = act_of(e)
	_dash_step(e)
	if act == 2 and not e.get("fence_on", false) and e.get("ishar_dash", {}).is_empty():
		e.fence_on = true
		var c: Vector2 = g.zone_c if g.zone_frozen else e.pos
		_dash_start(e, c, null, 0.8)
		e.ishar_fence = {"c": c, "r0": (g.zone_r if g.zone_frozen else 600.0) - 20.0, "t0": g.t, "next": g.t + 1.0}
		g.vfx.add_text(e.pos + Vector2(0, -80), "她沉入场心 · 歌声围拢", act_col(e), 18)
	# 一幕站定唱歌，但队长离开 320 以外她会慢慢走近（测试台 r9：完全不动时队伍走远打不到她，34% 超时）
	var far: bool = act == 0 and g.combat.ground_d(g.ppos, e.pos) > Bal.v("boss/ishar_a1_reach", 320.0)
	if not e.get("ishar_dash", {}).is_empty() or act == 2:
		e.spd = 0.0
	else:
		e.spd = float(e.spd_base) * (1.0 if far or act == 1 else 0.0)
	_fence_step(e)
	if g.t < float(e.get("rebirth_until", 0.0)) and int(e.get("web_n", 0)) <= 0:
		e.rebirth_until = g.t   # 重生之歌：网拆空当场结束
		g.vfx.add_text(e.pos + Vector2(0, -80), "歌声中断", COL, 15)


## 潮涌突进（二幕，取材「潮涌迫近」的位移，本作改编）：0.9 秒直线预警，之后 0.3 秒冲到队长身前 90 像素处（路径上 e.dmg × 0.6）；
## 落点就是这一组后面几招的发射点。目标点优先选队长与她之间、离队长最近的连线海嗣旁边，没有就直接冲向队长
func _surge(e: Dictionary) -> void:
	var to: Vector2 = g.ppos - (g.ppos - e.pos).normalized() * 90.0
	to = g.combat.arena_clamp(g.map.push_out(to, e.r), 90.0)
	var w: Dictionary = h._warn(e, "line", 0.9, {"pos": e.pos, "ang": (to - e.pos).angle(), "len": maxf(40.0, e.pos.distance_to(to)), "wid": 34.0,
		"act": "ishar_dash", "true": true, "name": "潮涌突进", "col": COL, "dmg": e.dmg * 0.6, "cancel_dead": true, "lock": true})
	_emit(e, g.t + w.dur, {"kind": "dash", "src": null, "to": to, "w": w})
	e.wind = maxf(e.wind, w.dur + 0.4)
	e.cdt = maxf(e.cdt, w.dur + 0.4)


func _dash_start(e: Dictionary, to: Vector2, w, dur: float) -> void:
	e.ishar_dash = {"a": e.pos, "b": to, "t0": g.t, "t1": g.t + dur, "w": w, "hit": false}
	g.fx.append({"kind": "ring", "pos": e.pos, "r": 40.0, "life": 0.4, "max": 0.4, "col": act_col(e), "enemy": true})
	_grains(e.pos, 12, "bfx_burst", false)
	if w is Dictionary:
		Sfx.play("tentacle", -4.0, 1.4)
		g.vfx.shake_screen(0.25)


func _dash_step(e: Dictionary) -> void:
	var d: Dictionary = e.get("ishar_dash", {})
	if d.is_empty():
		return
	var k: float = clampf((g.t - float(d.t0)) / maxf(0.01, float(d.t1) - float(d.t0)), 0.0, 1.0)
	var prev: Vector2 = e.pos
	e.pos = (d.a as Vector2).lerp(d.b, 1.0 - (1.0 - k) * (1.0 - k))
	if prev.distance_to(e.pos) > 4.0:
		g.fx.append({"kind": "tide_link", "a": prev, "b": e.pos, "life": 0.3, "max": 0.3, "col": act_col(e), "enemy": true})
	var w = d.get("w")
	if w is Dictionary and not d.hit and g.invuln <= 0.0:
		var hd: Dictionary = w.duplicate()
		hd.act = "ishar_line"
		if g.tele.hits_leader(hd):
			d.hit = true
			g.tele.warn_damage(hd)
	if k >= 1.0:
		e.ishar_dash = {}


## 歌声围拢（三幕）：场边一圈歌声从场地边缘（r0）在 boss/ishar_fence_t（18）秒内收到 boss/ishar_fence_min（320；380 时圈太大打不到她，260 时阵亡 42%）；
## 队长站在圈外：每 0.5 秒 e.dmg × boss/ishar_fence_tick（0.2）+ 减速 + 歌声侵蚀（受治疗降低）。圈内照常打
func _fence_r(e: Dictionary) -> float:
	var f: Dictionary = e.get("ishar_fence", {})
	if f.is_empty():
		return INF
	var k: float = clampf((g.t - float(f.t0)) / Bal.v("boss/ishar_fence_t", 18.0), 0.0, 1.0)
	return lerpf(float(f.r0), Bal.v("boss/ishar_fence_min", 320.0), k)


func _fence_step(e: Dictionary) -> void:
	var f: Dictionary = e.get("ishar_fence", {})
	if f.is_empty() or e.dead:
		return
	if g.combat.ground_d(g.ppos, f.c) <= _fence_r(e):
		return
	e.song_cut_until = g.t + 0.1
	if g.t < float(f.next):
		return
	f.next = g.t + 0.5
	g.combat.slow_leader("ishar_song", 0.6, 0.75)
	if g.invuln <= 0.0:
		g.tele.warn_damage({"owner": e, "act": "ishar_line", "name": "歌声围拢", "dmg": e.dmg * Bal.v("boss/ishar_fence_tick", 0.2), "true": true,
			"pos": f.c, "shape": "circle", "r": 1.0e6, "inner_r": _fence_r(e), "corrode": 0.0, "col": act_col(e)})   # 圈外才中：inner_r = 围拢半径
