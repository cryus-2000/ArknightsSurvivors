## Logos（术师·中坚，契约 v2.1，docs/26 第二批）：远程单体法伤 + 清场处决 + 反弹幕。
## 普攻「言」（2026-09-26 用户改：高速法术弹，不再是瞬发光线）：骨笔写下的咒文化作墨蓝法术弹高速飞向目标，命中后法伤并附「安魂」5 秒（受到的法术伤害 +15%，全队法伤受益，game.gd _damage 读 e.requiem）；
## S1 提喻：5 秒锁定一名敌人（优先精英 / Boss），每 0.25 秒法伤，对同一目标逐步升到 ×3、减速加深；
## S2 湮灭（永久）：射程 +30%、攻击 +50%；普攻处决生命低于攻击 ×1.5 的非精英敌人，溢出伤害转给随机另一名敌人；
## S3 延展敏锐：12 秒射程 +60%、攻击 +150%、同时 4 个目标；范围内敌方弹幕速度 -80%，结束时范围内弹幕全部消失。
## 天赋 词法演化：40% 概率额外攻击随机一名敌人（60% 伤害）并减速 0.8 秒。
## 可见成长（docs/25 §5）：N1 铭文 / N2 复指 / N4 转喻 / N5 墓志铭 / 精二质变 众声喧哗。
extends "res://scripts/characters/character.gd"

const INK := Color(0.55, 0.6, 1.0)
const PALE := Color(0.85, 0.9, 1.0)

var cd := 0.6
var perish := false           # S2 湮灭（永久）
var lock_t := 0.0             # S1 剩余
var lock_e = null
var lock_tick := 0.0
var lock_n := 0
var acuity_t := 0.0           # S3 剩余
# ---- 可见成长（docs/25 §5：只长咒文；原作依据 档案「用骨笔书写咒文」/ 天赋词法演化；命名用语言学术语）
var inscription := false      # N1「铭文」：命中处留下一枚发光咒文 1 秒，持续灼烧周围
var anaphora := false         # N2「复指」：每次「言」多打 1 个目标（70%）
var metonymy := false         # N4「转喻」：提喻目标死亡时链接跳到最近的敌人
var epitaph := false          # N5「墓志铭」：湮灭处决处写下大咒文，1 秒后爆开
var chorus := false           # 精二质变「众声喧哗」：词法演化的额外攻击打 2 名随机敌人
var glyphs: Array = []        # 铭文 {pos, t, tick, dmg, pat}
var bolts: Array = []         # 「言」法术弹 {pos, e, dmg, src, hist, life}（同时 ≤ 12）
const BOLT_MAX := 12
var epitaphs: Array = []      # 墓志铭 {pos, t, dmg, pat}
const RESIDUE_MAX := 6        # 铭文 + 墓志铭 同时存在的地面残留上限
## 咒文笔画（单位坐标 -1..1，每条 = 起点 → 终点）：几种像字又像符文的写法，随机取一种
const RUNES := [
	[[Vector2(0, -1), Vector2(0, 1)], [Vector2(-0.7, -0.5), Vector2(0.7, -0.5)], [Vector2(0, 1), Vector2(-0.45, 0.7)]],
	[[Vector2(-0.6, -0.6), Vector2(0.6, -0.6)], [Vector2(0.6, -0.6), Vector2(0.6, 0.6)], [Vector2(0.6, 0.6), Vector2(-0.6, 0.6)], [Vector2(-0.6, 0.6), Vector2(-0.6, -0.6)], [Vector2(-0.9, -1), Vector2(0.9, 1)]],
	[[Vector2(0, -1), Vector2(-0.8, 1)], [Vector2(-0.1, -0.2), Vector2(0.8, 1)], [Vector2(-0.6, -0.25), Vector2(0.6, -0.25)]],
	[[Vector2(-0.5, -1), Vector2(-0.5, 1)], [Vector2(-0.5, -0.6), Vector2(0.6, -1)], [Vector2(-0.5, 0), Vector2(0.6, -0.4)]],
	[[Vector2(-0.8, 0), Vector2(0.8, 0)], [Vector2(0, -1), Vector2(0, 1)], [Vector2(-0.55, -0.65), Vector2(-0.3, -0.4)], [Vector2(0.55, 0.45), Vector2(0.3, 0.7)]],
]


func _range() -> float:
	return base("range", 370.0) * stat(&"op_range") * (1.0 + base("s2_range", 0.3) if perish else 1.0) * (1.0 + base("s3_range", 0.6) if acuity_t > 0.0 else 1.0)


func _atk() -> float:
	return base("atk", 29.0) * _dmg_bonus() * (1.0 + base("s2_atk", 0.5) if perish else 1.0) * (1.0 + base("s3_atk", 1.5) * skill_power() if acuity_t > 0.0 else 1.0)


func update(dt: float) -> void:
	cd -= dt
	_update_lock(dt)
	_update_acuity(dt)
	_update_glyphs(dt)
	_update_bolts(dt)
	if acting():
		return
	var ready := charge_skills(dt)
	if ready >= 0:
		var ts: Array = nearest_enemies(1, _range(), pos)
		start_skill(ts[0].pos if not ts.is_empty() else Vector2.INF, ready)
		return
	if cd <= 0.0:
		var ts2: Array = nearest_enemies(1, _range(), pos)
		if ts2.is_empty():
			cd = 0.15
		else:
			cd = base("cd", 1.1) / stat(&"op_aspd")
			start_attack(ts2[0].pos)


## 「言」：单体法伤 + 安魂；精一天赋概率追加；湮灭处决
func _release() -> void:
	var n: int = int(base("s3_targets", 4.0)) if acuity_t > 0.0 else 1
	# N2 复指：多打 1 个目标，多出的这一道 70%
	var ts: Array = nearest_enemies(n + (1 if anaphora else 0), _range(), pos)
	if ts.is_empty():
		return
	for k in ts.size():
		_word(ts[k], _atk() * (base("second_mult", 0.7) if k >= n else 1.0), "言")
	# 天赋：50% 额外攻击随机一名敌人（60% 伤害）并减速；精二「众声喧哗」同时打 2 名
	if elite >= 1 and g.rng.randf() < base("talent_chance", 0.4):
		var pool: Array = nearest_enemies(8, _range(), pos)
		for q in (2 if chorus else 1):
			if pool.is_empty():
				break
			var e2: Dictionary = pool.pop_at(g.rng.randi() % pool.size())
			_word(e2, _atk() * base("talent_mult", 0.6), "词法演化")
			e2.slow = maxf(e2.slow, 0.8)
	Sfx.op(id, "atk", 0.0, 1.0, 0.08)


## 「言」出手：从手中射出一发高速法术弹（伤害结算在命中时，见 _word_hit）；弹数到上限时直接结算
func _word(e: Dictionary, dmg: float, src: String) -> void:
	if e.dead:
		return
	var hand: Vector2 = pos + Vector2(10.0 * face, -28)
	if bolts.size() >= BOLT_MAX:
		_word_hit(e, dmg, src)
		return
	bolts.append({"pos": hand, "e": e, "dmg": dmg, "src": src, "hist": [hand], "life": 1.2, "to": e.pos + Vector2(0, -e.r * 0.5)})
	fx({"kind": "glow", "pos": hand, "r": 7.0, "life": 0.1, "col": PALE, "alpha": 0.7})


## 法术弹飞行：base.bolt_speed（高速），追踪目标当前位置；目标半路死了就飞向它最后的位置、落地后找 60 内最近的敌人结算
func _update_bolts(dt: float) -> void:
	var spd: float = base("bolt_speed", 800.0)
	for b in bolts:
		b.life -= dt
		var e: Dictionary = b.e
		if not e.dead:
			b.to = e.pos + Vector2(0, -e.r * 0.5)
		var d: Vector2 = b.to - b.pos
		var step: float = spd * dt
		if d.length() <= step + 4.0:
			b.pos = b.to
			b.life = -1.0
			var tgt: Dictionary = e
			if e.dead:
				var near: Array = nearest_enemies(1, 60.0, b.to)
				tgt = near[0] if not near.is_empty() else {}
			if not tgt.is_empty():
				_word_hit(tgt, b.dmg, b.src)
			continue
		b.pos += d.normalized() * step
		b.hist.append(b.pos)
		if b.hist.size() > 6:
			b.hist.pop_front()
	bolts = bolts.filter(func(b): return b.life > 0.0)


## 「言」命中结算（原瞬发逻辑）：湮灭处决 / 伤害 + 安魂 / 铭文 / 溅射 / 命中特效
func _word_hit(e: Dictionary, dmg: float, src: String) -> void:
	if e.dead:
		return
	# 湮灭：处决非精英残血，溢出转给随机另一名敌人
	if perish and not e.elite and not e.boss and e.hp < _atk() * base("s2_exec", 1.5):
		var over: float = maxf(0.0, dmg - e.hp)
		log_hit("湮灭")
		deal_damage(e, e.hp + 1.0)
		Sfx.op(id, "big", -3.0)
		float_text(e.pos + Vector2(0, -e.r - 14), "湮灭", INK, 14)
		fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 16.0, "life": 0.3, "col": INK, "alpha": 0.7})
		# N5 墓志铭：在处决处写下一枚大咒文，1 秒后爆开
		# （同时最多 3 枚，写满时新的处决不再写字）
		if epitaph and epitaphs.size() < int(base("epitaph_max", 3.0)):
			_make_room()
			epitaphs.append({"pos": e.pos, "t": base("epitaph_delay", 1.0), "dmg": _atk() * base("epitaph_mult", 1.2), "pat": g.rng.randi() % RUNES.size()})
		if over > 0.0:
			var pool: Array = nearest_enemies(6, _range(), pos)
			pool = pool.filter(func(o): return not is_same(o, e) and not o.dead)
			if not pool.is_empty():
				var o: Dictionary = pool[g.rng.randi() % pool.size()]
				log_hit("言")
				deal_damage(o, over)
				o["requiem"] = base("requiem_dur", 5.0)
				var la: Vector2 = e.pos + Vector2(0, -e.r * 0.5)
				var lb: Vector2 = o.pos + Vector2(0, -o.r * 0.5)
				if g.tex.get("fx_logos_s1_link") != null:
					fx({"kind": "s1link", "pos": la, "to": lb, "life": 0.3})
				else:
					fx({"kind": "line", "pos": la, "to": lb, "life": 0.2, "col": INK, "w": 2.0})
		return
	log_hit(src)
	deal_damage(e, dmg)
	e["requiem"] = base("requiem_dur", 5.0)
	# N1 铭文：命中处留下一枚发光咒文（与墓志铭合计最多 6 枚，旧的先消失）
	if inscription:
		_make_room()
		if glyphs.size() + epitaphs.size() < RESIDUE_MAX:
			glyphs.append({"pos": e.pos, "t": base("glyph_dur", 1.0), "tick": base("glyph_tick", 0.25), "dmg": dmg * base("glyph_mult", 0.15), "pat": g.rng.randi() % RUNES.size()})
	# 命中处小范围溅射（纯单体清不动 1:15 的骨潮，同铃兰 P5.1 的处理）
	var ar: float = base("aoe", 30.0)
	if ar > 0.0:
		for j in query_ids(e.pos, ar + 20.0):
			var o: Dictionary = g.enemies[j]
			if o.dead or is_same(o, e) or o.pos.distance_to(e.pos) > ar + o.r:
				continue
			log_hit(src)
			deal_damage(o, dmg * base("aoe_mult", 0.45))
			o["requiem"] = base("requiem_dur", 5.0)
	# 命中处墨蓝爆点（弹体自己画在 _draw_skill_over；这里不再拉瞬发光线）
	# Codex 骨笔符文（命中单次播放）；缺图退回墨蓝爆点 / 光点
	if not spawn_fx_sprite("fx_logos_glyph", e.pos + Vector2(0, -e.r * 0.5), g.PX, 0.0, g.rng.randf() < 0.5) \
			and not spawn_fx_sprite("fx_ink_hit", e.pos + Vector2(0, -e.r * 0.5), g.PX * 0.9, 0.0, g.rng.randf() < 0.5):
		fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 10.0, "life": 0.22, "col": PALE, "alpha": 0.6})
	for k in 3:
		fx({"kind": "mote", "pos": e.pos + Vector2(g.rng.randf_range(-8, 8), -e.r * 0.5 + g.rng.randf_range(-8, 8)), "vel": Vector2(0, -40), "life": 0.35, "col": INK, "sz": 2.0})


# ---------------------------------------------------------------- 技能

func _release_skill() -> void:
	match cur_skill:
		0:
			# 提喻：锁定精英 / Boss 优先
			var best = null
			var bd := INF
			for j in query_ids(pos, _range()):
				var e: Dictionary = g.enemies[j]
				if e.dead:
					continue
				var score: float = e.pos.distance_to(pos) - (100000.0 if (e.elite or e.boss) else 0.0)
				if score < bd:
					bd = score
					best = e
			if best == null:
				sp[0] = sp_need(0) * 0.6
				return
			lock_e = best
			lock_t = base("s1_dur", 5.0)
			lock_tick = 0.0
			lock_n = 0
			spawn_fx_sprite("fx_circle_ink", best.pos + Vector2(0, best.r * 0.8), g.PX * clampf(best.r / 14.0, 1.2, 2.6))
			float_text(best.pos + Vector2(0, -best.r - 16), "提喻", INK, 15)
		1:
			perish = true
			show_banner("湮灭：攻击范围与攻击永久提升，处决残血")
			fx({"kind": "ring", "pos": pos, "r": 56.0, "r0": 8.0, "life": 0.5, "col": INK, "floor": true})
			spawn_fx_sprite("fx_logos_s2", pos + Vector2(0, -16), g.PX * 0.7)   # 已购 CodeManu felspell 按 ink 色板重上色（tools/fx_import.py）
		2:
			acuity_t = base("s3_dur", 12.0)
			show_banner("延展敏锐")
			spawn_fx_sprite("fx_holy_pillar_ink", pos + Vector2(0, 4), g.PX * 1.3, 0.0, false, true)
			spawn_fx_sprite("fx_circle_ink", pos + Vector2(0, 4), g.PX * 2.4)
			g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -26), "life": 0.6, "max": 0.6, "col": INK})
			fx({"kind": "ring", "pos": pos, "r": _range(), "r0": 30.0, "life": 0.8, "col": INK, "floor": true, "w": 2.0})
	# 技能发动音 op_logos_s1/s2/s3 由 spend_sp 播放


func skill_active_left(i: int) -> float:
	match i:
		0: return lock_t
		2: return acuity_t
	return 0.0


func skill_active_dur(i: int) -> float:
	return [base("s1_dur", 5.0), 1.0, base("s3_dur", 12.0)][i]


func _update_lock(dt: float) -> void:
	if lock_t <= 0.0:
		return
	lock_t -= dt
	if lock_e != null and lock_e.dead and metonymy and lock_t > 0.0:
		_metonymy_jump()
	if lock_e == null or lock_e.dead:
		lock_t = 0.0
		lock_e = null
		return
	lock_tick += dt
	var tick: float = base("s1_tick", 0.25)
	while lock_tick >= tick:
		lock_tick -= tick
		lock_n += 1
		var ramp: float = lerpf(1.0, base("s1_max", 3.0), clampf(lock_n / 12.0, 0.0, 1.0))
		log_hit("提喻")
		deal_damage(lock_e, _atk() * base("s1_tick_mult", 0.5) * ramp * skill_power())
		lock_e.slow = maxf(lock_e.slow, 0.6 * ramp)
		fx({"kind": "line", "pos": pos + Vector2(10.0 * face, -28), "to": lock_e.pos + Vector2(0, -lock_e.r * 0.5), "life": 0.12, "col": INK, "w": 1.5 + ramp})
		fx({"kind": "glow", "pos": lock_e.pos + Vector2(0, -lock_e.r * 0.5), "r": 8.0 + 6.0 * ramp, "life": 0.2, "col": PALE, "alpha": 0.5})


## N4 转喻：提喻目标死亡，链接跳到离它最近的敌人（射程内），剩余时间与叠层照旧
func _metonymy_jump() -> void:
	var from: Vector2 = lock_e.pos
	var best = null
	var bd: float = INF
	for j in query_ids(from, _range()):
		var o: Dictionary = g.enemies[j]
		if o.dead or o.pos.distance_to(pos) > _range():
			continue
		var d: float = o.pos.distance_to(from)
		if d < bd:
			bd = d
			best = o
	if best == null:
		return
	lock_e = best
	var to: Vector2 = best.pos + Vector2(0, -best.r * 0.5)
	# 链接跳转：一道墨蓝折线从旧目标弹到新目标 + 新目标脚下的锁定圈
	var mid: Vector2 = (from + to) * 0.5 + Vector2(0, -24)
	fx({"kind": "line", "pos": from + Vector2(0, -8), "to": mid, "life": 0.3, "col": PALE, "w": 2.5})
	fx({"kind": "line", "pos": mid, "to": to, "life": 0.3, "col": PALE, "w": 2.5})
	fx({"kind": "ring", "pos": best.pos, "r": best.r + 18.0, "r0": 4.0, "life": 0.35, "col": INK, "floor": true})
	spawn_fx_sprite("fx_circle_ink", best.pos + Vector2(0, best.r * 0.8), g.PX * clampf(best.r / 14.0, 1.2, 2.6))
	float_text(best.pos + Vector2(0, -best.r - 16), "转喻", INK, 14)


## 铭文 / 墓志铭的地面残留超过上限时，先挤掉最旧的铭文
func _make_room() -> void:
	while glyphs.size() + epitaphs.size() >= RESIDUE_MAX and not glyphs.is_empty():
		glyphs.pop_front()


## 铭文每 0.25 秒灼烧 30 内的敌人；墓志铭到点爆开
func _update_glyphs(dt: float) -> void:
	if not glyphs.is_empty():
		var gr: float = base("glyph_r", 30.0)
		for gl in glyphs:
			gl.t -= dt
			gl.tick -= dt
			if gl.tick <= 0.0 and gl.t > -0.01:
				gl.tick += base("glyph_tick", 0.25)
				for j in query_ids(gl.pos, gr + 20.0):
					var e: Dictionary = g.enemies[j]
					if e.dead or e.pos.distance_to(gl.pos) > gr + e.r:
						continue
					log_hit("铭文")
					deal_damage(e, gl.dmg)
		glyphs = glyphs.filter(func(gl): return gl.t > 0.0)
	if not epitaphs.is_empty():
		for ep in epitaphs:
			ep.t -= dt
			if ep.t <= 0.0:
				_epitaph_burst(ep)
		epitaphs = epitaphs.filter(func(ep): return ep.t > 0.0)


func _epitaph_burst(ep: Dictionary) -> void:
	ep.t = 0.0
	var r: float = base("epitaph_r", 70.0)
	area_hit("墓志铭", ep.pos, r, ep.dmg)
	fx({"kind": "ring", "pos": ep.pos, "r": r, "r0": 10.0, "life": 0.4, "col": INK, "floor": true, "w": 3.0})
	fx({"kind": "ring", "pos": ep.pos, "r": r * 0.7, "r0": 6.0, "life": 0.3, "col": PALE, "floor": true, "w": 2.0})
	fx({"kind": "glow", "pos": ep.pos + Vector2(0, -20), "r": 34.0, "life": 0.35, "col": INK, "alpha": 0.6})
	spawn_fx_sprite("fx_logos_glyph", ep.pos + Vector2(0, -20), g.PX * 1.4)
	fx_sparks(ep.pos + Vector2(0, -20), PALE, 10, 200.0, 0.45, 2.5)
	Sfx.op(id, "big", -6.0, 1.2)


func _update_acuity(dt: float) -> void:
	if acuity_t <= 0.0:
		return
	acuity_t -= dt
	var r := _range()
	var f: float = base("s3_bullet_slow", 0.2)
	for b in g.ebullets:
		if b.life <= 0.0 or b.pos.distance_to(pos) > r:
			continue
		if not b.get("acuity", false):
			b["acuity"] = true
			b.vel *= f
			b.life = b.life / f
	if acuity_t <= 0.0:
		# 结束：范围内弹幕全部消失
		var n := 0
		for b in g.ebullets:
			if b.life > 0.0 and b.pos.distance_to(pos) <= r:
				b.life = 0.0
				n += 1
				fx({"kind": "glow", "pos": b.pos, "r": 8.0, "life": 0.25, "col": INK, "alpha": 0.6})
		if n > 0:
			float_text(pos + Vector2(0, -70), "消除弹幕 ×%d" % n, INK, 15)
		fx({"kind": "ring", "pos": pos, "r": r, "r0": r * 0.5, "life": 0.5, "col": INK, "floor": true})


# ---------------------------------------------------------------- 成长节点（data/characters/logos.json 的 custom 节点）

func on_custom_node(nid: String, _choice: String = "") -> void:
	match nid:
		"inscription":
			inscription = true
		"anaphora":
			anaphora = true
		"metonymy":
			metonymy = true
		"epitaph":
			epitaph = true


func on_elite(stage: int, _choice: String = "") -> void:
	if stage >= 2:
		chorus = true


# ---------------------------------------------------------------- 绘制

## 一枚咒文：按笔顺逐笔写出（write 0..1），暗色描边 + 墨蓝笔画 + 亮芯；顶点对齐 2 像素网格
func _draw_rune(c: Vector2, sz: float, pat: int, write: float, al: float) -> void:
	var strokes: Array = RUNES[pat % RUNES.size()]
	var ns: int = strokes.size()
	for i in ns:
		var k: float = clampf(write * ns - i, 0.0, 1.0)
		if k <= 0.0:
			break
		var a: Vector2 = ((c + strokes[i][0] * sz) / 2.0).round() * 2.0
		var b: Vector2 = ((c + (strokes[i][0].lerp(strokes[i][1], k)) * sz) / 2.0).round() * 2.0
		g.draw_line(a, b, Color(0.03, 0.03, 0.08, 0.7 * al), 4.0)
		g.draw_line(a, b, Color(INK.r * 1.5, INK.g * 1.5, INK.b * 1.8, 0.95 * al), 2.0)
		g.draw_line(a, b, Color(1.8, 1.9, 2.4, 0.6 * al), 1.0)


## 地面层：铭文 / 墓志铭脚下的书写圈
func draw_entities_floor() -> void:
	for gl in glyphs:
		var al: float = clampf(gl.t / 0.3, 0.0, 1.0)
		g.draw_set_transform(gl.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
		g.draw_circle(Vector2.ZERO, base("glyph_r", 30.0), Color(INK.r, INK.g, INK.b, 0.1 * al))
		g.draw_arc(Vector2.ZERO, base("glyph_r", 30.0), 0.0, TAU, 24, Color(INK.r * 1.3, INK.g * 1.3, INK.b * 1.5, 0.45 * al), 1.5)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for ep in epitaphs:
		var k: float = 1.0 - ep.t / base("epitaph_delay", 1.0)
		var r: float = base("epitaph_r", 70.0)
		g.draw_set_transform(ep.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
		g.draw_circle(Vector2.ZERO, r, Color(INK.r, INK.g, INK.b, 0.08 + 0.12 * k))
		g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(INK.r * 1.4, INK.g * 1.4, INK.b * 1.7, 0.4 + 0.4 * k), 2.0)
		g.draw_arc(Vector2.ZERO, r * k, 0.0, TAU, 40, Color(PALE.r, PALE.g, PALE.b, 0.5), 1.5)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_auras() -> void:
	if acuity_t > 0.0 and pos != Vector2.INF:
		g.draw_set_transform(pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		g.draw_arc(Vector2.ZERO, _range(), 0.0, TAU, 60, Color(INK.r, INK.g, INK.b, 0.18 + 0.06 * sin(g.t * 3.0)), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_skill_over() -> void:
	# 「言」法术弹：墨蓝拖尾（最近 6 个位置渐细）+ 淡蓝亮芯 + 外圈微光
	for b in bolts:
		var h: Array = b.hist
		for i in range(1, h.size()):
			var k: float = float(i) / float(h.size())
			g.draw_line(h[i - 1], h[i], Color(INK.r, INK.g, INK.b, 0.25 + 0.55 * k), 1.5 + 6.0 * k)
		if g.tex.get("proj_logos_ink") != null and h.size() >= 2:
			# Codex 墨蓝尖头法术弹（朝右），按飞行方向旋转；保留拖尾、去掉圆亮芯
			draw_spr_rot("proj_logos_ink", int(g.t * 12.0) % 4, b.pos, (b.pos - h[h.size() - 2]).angle(), g.PX)
		else:
			g.draw_circle(b.pos, 10.0, Color(INK.r, INK.g, INK.b, 0.35))
			g.draw_circle(b.pos, 5.5, Color(INK.r * 1.4, INK.g * 1.4, INK.b * 1.6))
			g.draw_circle(b.pos, 2.5, Color(1.8, 1.9, 2.2))
	# 铭文：命中处浮着一枚发光咒文（0.15 秒内逐笔写出，最后 0.3 秒淡出）
	for gl in glyphs:
		var life: float = base("glyph_dur", 1.0)
		var al: float = clampf(gl.t / 0.3, 0.0, 1.0)
		var bob: float = sin(g.t * 5.0 + gl.pat) * 1.5
		g.draw_circle(gl.pos + Vector2(0, -16 + bob), 13.0, Color(INK.r, INK.g, INK.b, 0.18 * al))
		_draw_rune(gl.pos + Vector2(0, -16 + bob), 9.0, gl.pat, (life - gl.t) / 0.15, al)
	# 墓志铭：大咒文在 1 秒内一笔一笔写完，越写越亮，写完即爆
	for ep in epitaphs:
		var k: float = 1.0 - ep.t / base("epitaph_delay", 1.0)
		var c: Vector2 = ep.pos + Vector2(0, -26)
		g.draw_circle(c, 18.0 + 6.0 * k, Color(INK.r, INK.g, INK.b, 0.12 + 0.2 * k))
		_draw_rune(c, 16.0, ep.pat, k * 1.25, 0.7 + 0.3 * k)
	if lock_t > 0.0 and lock_e != null and not lock_e.dead and g.tex.get("fx_logos_script") != null:
		# 提喻：一行骨笔符文从手边流向目标（64×12 书写带平铺，4 帧循环）
		var hand: Vector2 = pos + Vector2(10.0 * face, -28)
		var to: Vector2 = lock_e.pos + Vector2(0, -lock_e.r * 0.5)
		_draw_tiled("fx_logos_script", hand, to, g.PX * 0.8, fmod(g.t * 210.0, 64.0 * g.PX * 0.8))
	if lock_t > 0.0 and lock_e != null and not lock_e.dead:
		var p: Vector2 = lock_e.pos + Vector2(0, -lock_e.r - 14)
		var k: float = 0.5 + 0.5 * sin(g.t * 8.0)
		g.draw_arc(p, 6.0 + 2.0 * k, 0.0, TAU, 12, Color(INK.r, INK.g, INK.b, 0.9), 1.5)
		g.draw_line(p + Vector2(-9, 0), p + Vector2(-4, 0), PALE, 1.5)
		g.draw_line(p + Vector2(4, 0), p + Vector2(9, 0), PALE, 1.5)
	if acuity_t > 0.0:
		var q := pos + Vector2(0, -44)
		g.draw_circle(q, 3.0 + sin(g.t * 12.0), Color(INK.r * 1.6, INK.g * 1.6, INK.b * 1.4, 0.8))


## 沿 a→b 平铺一张横向帧条（每段 64px 宽的帧），offset 为沿方向的滚动位移（屏幕像素）；最后一段按端点裁剪，不越过目标
func _draw_tiled(tn: String, a: Vector2, b: Vector2, sc: float, offset: float, frame_off: int = 0, col := Color.WHITE) -> void:
	var tx: Texture2D = g.tex.get(tn)
	if tx == null:
		return
	var frames: int = g.V6_FRAMES[tn][0]
	var fw: float = tx.get_width() / frames
	var fh: float = tx.get_height()
	var k: float = sc / A.hires_of(tx)
	var seg: float = fw * k                               # 一段在屏幕上的长度
	var L: float = a.distance_to(b)
	if L < 2.0:
		return
	var fr: int = (int(g.t * 12.0) + frame_off) % frames
	g.draw_set_transform(a + g.draw_off, (b - a).angle(), Vector2(k, k))
	var x: float = -fmod(offset, seg)
	while x < L:
		var x0: float = maxf(x, 0.0)
		var x1: float = minf(x + seg, L)
		if x1 > x0:
			var u0: float = (x0 - x) / k
			var u1: float = (x1 - x) / k
			g.draw_texture_rect_region(tx, Rect2(Vector2(x0 / k, -fh / 2.0), Vector2(u1 - u0, fh)), Rect2(fw * fr + u0, 0, u1 - u0, fh), col)
		x += seg
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## S3 延异视阈：绕身旋转的符咒，拆成人物后 / 前两层（同一相位、同一中心锚点）
func _acuity_layer(front: bool) -> void:
	if acuity_t <= 0.0 or pos == Vector2.INF:
		return
	var tn: String = "fx_logos_s3_front" if front else "fx_logos_s3_back"
	if g.tex.get(tn) == null:
		if front and g.tex.get("fx_logos_s3_orbit") != null:
			draw_spr_rot("fx_logos_s3_orbit", int(g.t * 10.0) % 6, pos + Vector2(0, -36), 0.0, g.PX, Color(1, 1, 1, 0.95), Vector2(-1, -1), face < 0.0)
		return
	draw_spr_rot(tn, int(g.t * 10.0) % 6, pos + Vector2(0, -36), 0.0, g.PX, Color(1, 1, 1, 0.95), Vector2(-1, -1), face < 0.0)


func draw_body() -> void:
	_acuity_layer(false)
	super()
	_acuity_layer(true)


func _draw_pfx(f: Dictionary, a: float) -> bool:
	if f.kind == "s1link":
		# 湮灭余伤传递：黑色咒文联系，全不透明、从起点铺向目标
		var grow: float = minf(1.0, (1.0 - a) / 0.3)
		_draw_tiled("fx_logos_s1_link", f.pos, f.pos.lerp(f.to, grow), g.PX * 0.8, 0.0)
		return true
	return false


func status_items() -> Array:
	var out: Array = []
	if lock_t > 0.0:
		out.append(["提喻", INK])
	if acuity_t > 0.0:
		out.append(["延展敏锐", INK])
	return out
