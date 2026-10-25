## 敌方投射物池（docs/101 B7 ④，10-15 从 run/enemies.gd 搬来）：抛物（g.lobs）、敌弹（g.ebullets）、冲击环（g.shocks）的推进合在一个
## step(dt) 里按固定次序走：抛物 → 敌弹 → 冲击环（冲击环原在 enemies.update_status 的溟痕之后，B7 起排到状态结算之前）。
## 三张表仍挂在 g 上：生产点（enemy_ai / boss_patterns / telegraph / Boss 脚本）与绘制（world）照旧读写；热字段平行数组留给 B8，
## 将来的原生 EnemyShotPool.step 替换这里的函数体（docs/101 §4.2 ②）
extends RefCounted

const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")
const Game = preload("res://scripts/game.gd")
var g: Game


func _init(game: Game) -> void:
	g = game


func step(dt: float) -> void:
	update_lobs(dt)
	update_ebullets(dt)
	update_shocks(dt)


func update_lobs(dt: float) -> void:
	for l in g.lobs:
		l.t += dt
		if l.t >= l.dur and g.beacon_sys.bullet_eaten(l.to):
			g.beacon_sys.eat_fx(l.to)   # 圈内安全：落进读条光圈的抛石被灯光吞掉，不伤人、不留溟痕（docs/49g）
			continue
		if l.t >= l.dur:
			if l.get("kind", "") == "brood":
				_brood_land(l)
			else:
				# 落点帧条（enemies.json land_fx，docs/96 §1.4 喷吐者 fx_spitter_land，地面层、原点 (20,17)）：有图就不画程序爆圈 / 石屑火花；溟痕照旧由下面接管
				var landed: bool = str(l.get("land_fx", "")) != "" and g.vfx.fx_sprite(l.land_fx, l.to, Game.PX, 0.0, false, false, Color.WHITE, true, Vector2(20, 17))
				if not landed:
					g.fx.append({"kind": "explode", "pos": l.to, "r": l.r, "life": 0.35, "max": 0.35, "col": Color(0.5, 0.9, 0.5) if l.get("mire", false) else Color(0.8, 0.7, 0.55)})
				# 最终 Boss 禁生成区域按溟痕最大半径检查，区域外照常留痕。
				if l.get("mire", false) and not g.combat.mire_blocked(l.to, 44.0):
					g.combat.add_enemy_mire({"pos": l.to, "r": 12.0, "maxr": 44.0, "life": 7.0, "seed": g.vrng.randf() * 100.0}, "lob")
				if not landed:
					g.vfx.sparks(l.to, Vector2.ZERO, Color(0.75, 0.7, 0.6), 8, 200.0)
				Sfx.play("boom", -14.0, 1.6, 0.1)
			if g.combat.ground_d(g.ppos, l.to) < l.r and g.invuln <= 0.0:   # 画即判（§1.9）
				g.combat.enemy_hit(l.dmg * Bal.v("enemy/bullet_dmg_mult", 1.0), l, false, false, ["远程", "法术"], "bullet")
				if str(l.get("hit_fx", "")) != "":
					g.vfx.fx_sprite(l.hit_fx, g.ppos + Vector2(0, -8), Game.PX, 0.0, false, false, Color.WHITE, false, Vector2(float(l.get("hit_org", [12, 19])[0]), float(l.get("hit_org", [12, 19])[1])))   # 队长中酸：侵蚀命中帧条（紫蓝变体）
	g.lobs = g.lobs.filter(func(l): return l.t < l.dur)


## 投嗣弹落地（投嗣育母，用户 10-14 定；enemy_ai.lob 的 lob_kind brood）：酸液砸开 + 在落点孵化一只注亡拟嗣。
## 画面：fx_brood_land（docs/96 §1.1，粘液破开 → 拟嗣展开；播完前拟嗣本体不画、不接触、不吐酸：e.hatch_until）；
## 缺图时 fx_acid_splash + 拟嗣直接出现。场上拟嗣到 spawner.type_cap 只造成伤害不孵化（伤害在 update_lobs 统一结算）
func _brood_land(l: Dictionary) -> void:
	var kind: String = str(l.get("spawn", "brood"))
	var cap: int = g.spawner.type_cap(kind)
	var can_hatch: bool = cap <= 0 or g.spawner.type_n(kind) < cap
	var hp: Vector2 = g.map.push_out(l.to, 10.0) if can_hatch else l.to   # 孵化点（避开景物），落地帧条对齐到它
	var hatch := 0.0
	# Codex enemy_fx_1：fx_brood_land 24×24，末帧含 e_brood f0（1x 嵌入偏移 (3,4)）→ 原点 (12,24) 正好是拟嗣脚底锚点，播完移交本体
	if g.vfx.fx_sprite("fx_brood_land", hp, Game.PX, 0.0, false, false, Color.WHITE, false, Vector2(12, 24)):
		var spec: Array = Game.V6_FRAMES["fx_brood_land"]
		hatch = float(spec[0]) / float(spec[1])
	else:
		g.vfx.fx_sprite("fx_acid_splash", l.to + Vector2(0, 6), Game.PX, 0.0, false, true)
	g.fx.append({"kind": "ring", "pos": l.to, "r": l.r, "life": 0.3, "max": 0.3, "col": Color(1.0, 0.3, 0.72)})   # 敌方洋红（docs/48）
	g.vfx.sparks(l.to, Vector2.ZERO, Color(0.9, 1.6, 0.5), 8, 160.0)   # 酸绿粘液
	Sfx.play("mire_splat", -10.0, 1.1, 0.1)
	if not can_hatch:
		return
	var nb: Dictionary = g.spawner.spawn_enemy(kind, hp)
	if hatch > 0.0:
		nb["hatch_until"] = g.t + hatch
		nb.cdt = maxf(nb.cdt, hatch)   # 展开期间不吐酸


## 干员接口（docs/101 §7.3.10）：pred(pos) 为真的活敌弹减速 f 倍、寿命同比延长；每颗只减一次（tag 记在弹上）
func slow_in(pred: Callable, f: float, tag: String) -> void:
	for bl in g.ebullets:
		if bl.life <= 0.0 or not pred.call(bl.pos):
			continue
		if not bl.get(tag, false):
			bl[tag] = true
			bl.vel *= f
			bl.life = bl.life / f


## 干员接口：pred(pos) 为真的活敌弹立即消除；返回被消除的位置（调用方按位置播画面，个数 = size()）
func cancel_in(pred: Callable) -> PackedVector2Array:
	var out := PackedVector2Array()
	for bl in g.ebullets:
		if bl.life > 0.0 and pred.call(bl.pos):
			bl.life = 0.0
			out.append(bl.pos)
	return out


func update_ebullets(dt: float) -> void:
	for b in g.ebullets:
		if b.life <= 0.0:
			continue
		if b.get("home", false):
			var want: Vector2 = (g.ppos + Vector2(0, -14) - b.pos).normalized() * b.vel.length()
			b.vel = b.vel.lerp(want, clampf(dt * 1.6, 0.0, 1.0))
		b.pos += b.vel * dt
		b.life -= dt
		if not b.get("boss", false) and g.beacon_sys.bullet_eaten(b.pos):
			b.life = 0.0   # 圈内安全：非 Boss 子弹进入读条光圈即消散（docs/49g）
			g.beacon_sys.eat_fx(b.pos)
			continue
		# 地形阻挡：敌方直线弹撞景物底座即消失（酸弹溅开 / 神经弹留溟痕照常走 life <= 0 分支）；追踪弹与预警类弹幕（no_rock）不挡，Boss 弹看 terrain/block_boss_bullets
		var rock: bool = g.map.tb_ebul and not b.get("home", false) and (g.map.tb_boss or not b.get("boss", false)) and not b.has("no_rock") and g.map.bullet_blocked(b, b.pos, true)
		if rock:
			b.life = 0.0
		var hitp: bool = not rock and b.pos.distance_to(g.ppos + Vector2(0, -14)) < b.r + 12.0
		if b.get("kind", "") == "acid" and (hitp or b.life <= 0.0):
			g.vfx.fx_sprite("fx_acid_splash", b.pos + Vector2(0, 6), Game.PX, 0.0, false, true)   # Codex v14 酸团落地 / 命中溅开
		if b.get("mire", false) and (hitp or b.life <= 0.0) and (not b.get("boss", false) or g.mires.size() < 48) and _boss_mire_ok(b) and (b.get("boss", false) or not g.combat.mire_blocked(b.pos + Vector2(0, 10), float(b.get("mire_r", 52.0)))):
			var bm: bool = b.get("boss", false)
			# Boss 溟痕（docs/38 §1.7）：每块最多 6 秒（原来 10 秒）
			# 小怪子弹留的溟痕按来源定大小 / 时长（浮海飘航者的神经弹：半径 30、5 秒，协调人 9/29 定 A；站进去累积神经损伤）
			var bmire := {"pos": b.pos + Vector2(0, 10), "r": 10.0, "maxr": float(b.get("mire_r", 52.0)), "life": 6.0 if bm else float(b.get("mire_life", 10.0)), "seed": g.vrng.randf() * 100.0, "boss": bm}
			if bm:
				g.mires.append(bmire)   # Boss 溟痕是招式残留，照旧按 life 到期，不进怪物溟痕计数
			else:
				g.combat.add_enemy_mire(bmire, "shot")
			if not bm and b.has("mire_r"):
				Sfx.play("mire_splat", -10.0, 1.0, 0.1)   # 神经弹落地留溟痕
		if hitp:
			b.life = 0.0
			if str(b.get("hit_fx", "")) != "":
				g.vfx.fx_sprite(b.hit_fx, b.pos + Vector2(0, -10), Game.PX, 0.0, false, false, Color.WHITE, false, Vector2(float(b.get("hit_org", [12, 19])[0]), float(b.get("hit_org", [12, 19])[1])))   # 专属命中帧条（docs/96 §1.2 漂移体 fx_corrode_hit，原点 (12,19)，纯画面）
			if b.get("slow", false) and not g.combat.atk_slow_as_slow(3.0, b.get("boss", false)):   # Boss 来源不写 atk_slow（docs/38 §1.11）
				g.atk_slow = 3.0
			if g.invuln <= 0.0:
				g.combat.enemy_hit(b.dmg * Bal.v("enemy/bullet_dmg_mult", 1.0), b, b["true"], false, ["远程", "真实" if b["true"] else b.get("atk", "法术")], "bullet")


## Boss 溟痕上限（docs/38 §1.7）：同时最多 12 块；场地冻结后不生成在离圈边 120 以内。
## 最终场地的禁生成区只挡非 Boss 溟痕（combat.mire_blocked），Boss 弹的溟痕是招式本身，照旧留在场内
func _boss_mire_ok(b: Dictionary) -> bool:
	if not b.get("boss", false):
		return true
	var n := 0
	for m in g.mires:
		if m.get("boss", false):
			n += 1
	if n >= int(Bal.v("boss/mire_max", 12.0)):
		return false
	return not g.zone_frozen or b.pos.distance_to(g.zone_next_c) < g.zone_next_r - 120.0


## 冲击环：环带宽 22、按地面椭圆判，命中一次；缺口环站在缺口里不中
func update_shocks(dt: float) -> void:
	for s in g.shocks:
		s.r += float(s.get("spd", 320.0)) * dt   # spd：缺口环（大群之歌）扩散 ≤220px/s（docs/38 §1.9），普通冲击环 320
		# 冲击环：环带宽 22，按地面椭圆算，且不超过最大半径（= 预警圈，docs/38 B0 第 5 项、docs/48 P0-1）
		var sd: float = g.combat.ground_d(g.ppos, s.pos)
		if not s.hit and absf(sd - s.r) < 22.0 and sd <= s.maxr and not g.tele.in_gap(s, (g.ppos - s.pos).angle()):   # 缺口环：站在缺口弧里不算中（docs/95 §12 song_ring）
			s.hit = true
			if g.invuln <= 0.0:
				if not g.combat.stun_as_slow(s.get("boss", false)):   # Boss 战里僵直改成减速（docs/38 §1.11）
					g.pstun = max(g.pstun, 0.5)
				# 来源名：遥测分得出是谁的冲击环；src_type 不进受击字典，免得奠基者踏地额外带上寒霜
				g.combat.enemy_hit(s.dmg, {"boss": s.get("boss", false)}, true, true, ["近战", "真实"] if s.get("true", false) else ["近战", "物理"],
					"shock_" + str(s.src_type) if s.has("src_type") else "shock")   # 冲击环的 boss 标记由放招的敌人决定（boss_ai.gd）
	g.shocks = g.shocks.filter(func(s): return s.r < s.maxr)
