extends RefCounted
## 刷怪：按波次表（data/waves.json）和威胁曲线在屏幕外刷怪、刷精英 / 宝箱 / 拟态箱，生成敌人字典。
## 敌人的行为在 enemies/enemy_ai.gd，敌人的逐帧更新仍在 game.gd _update_enemies。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json 数值旋钮（docs/27）

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
const MAX_ENEMIES := 450
var next_id := 0
var spawn_acc := 0.0
var next_elite: float = Bal.v("enemy/first_elite", 45.0)   # 首只精英出现时间（balance.json）
var horde_warned := -1.0
var boss_idx := 0
var mid_used: Array = []
## 同一人物的不同档（docs/38 §2.2，用户 10-01 按原作核对：圣徒卡门 / 圣徒伊比利亚是同一人两档）：中期 Boss 抽取按人物排除，同局只出一位
const SAME_PERSON := {"carmen": "saint", "iberia": "saint"}
var next_chest := 20.0
var fading: Array = []   # 最终 Boss 登场时排队消散的杂兵（final/clear_mobs_s > 0 才有；元素 [敌人, 消散时刻]）


func _init(game: Game) -> void:
	g = game


func edge_pos() -> Vector2:
	var ang: float = g.rng.randf() * TAU
	var dist: float = g.rng.randf_range(720.0, 820.0)
	# 背光刷怪（docs/56 候选 e，beacon/shade_deg > 0 开）：朝向未点燃灯标 ±shade_deg 的扇区不刷杂兵。
	# 不重掷：把 [0, TAU) 的随机角均匀映射到扇区以外的那段弧上，随机数调用次数与旋钮无关，同 seed 同旋钮可复现
	var sh: Array = g.beacon_sys.shade_sector()
	if not sh.is_empty():
		var half: float = sh[1]
		var u: float = fposmod(ang - (sh[0] + half), TAU)   # 从扇区末端起量的角度 [0, TAU)
		ang = sh[0] + half + u * (TAU - 2.0 * half) / TAU
	return g.ppos + Vector2.from_angle(ang) * dist


## 持续缩圈中的非战斗交互物，保留立绘与交互的安全边距。
func safe_event_pos(p: Vector2, margin := 100.0) -> Vector2:
	if g.zone_state == 0:
		return p
	var lim: float = maxf(0.0, g.zone_r - margin)
	var d: Vector2 = p - g.zone_c
	return p if d.length() <= lim else g.zone_c + d.normalized() * lim


## 在有效圈内挑离玩家足够远的候选；极小圈不可能满足距离时选最远的可达点。
func event_pos(min_distance: float, max_distance: float, margin := 100.0) -> Vector2:
	var start: float = g.rng.randf() * TAU
	var radius: float = g.rng.randf_range(min_distance, max_distance)
	var best := safe_event_pos(g.ppos, margin)
	var best_d := -1.0
	for i in 16:
		var p := safe_event_pos(g.ppos + Vector2.from_angle(start + i * TAU / 16.0) * radius, margin)
		var distance := p.distance_to(g.ppos)
		if distance > best_d:
			best = p
			best_d = distance
		if distance >= min_distance:
			return p
	return best


func pick_type() -> String:
	var pool: Array = D.THREAT[g.threat].pool
	var pick: String = ""
	var fw := final_knob("trickle_fresh_w", 1.0) if trickling() else 1.0
	if fw != 1.0 and g.threat > 0:
		# 最终 Boss 战少量补怪（docs/38 §8.14 10-12）：本级威胁新出现的种类（上一级池里没有的）权重 × trickle_fresh_w，池里重复项照常算权重
		var prev: Array = D.THREAT[g.threat - 1].pool
		var ws: Array = []
		var tot := 0.0
		for x in pool:
			var w := maxf(0.0, fw) if not prev.has(x) else 1.0
			ws.append(w)
			tot += w
		var r := g.rng.randf() * tot
		pick = pool[pool.size() - 1]
		for k in pool.size():
			r -= float(ws[k])
			if r < 0.0:
				pick = pool[k]
				break
	else:
		pick = pool[g.rng.randi() % pool.size()]
	if type_cap(pick) > 0 and type_n(pick) >= dens_cap(type_cap(pick)):   # 同种上限按怪物密度同比缩（density 1 = 原值）
		pick = "slider" if g.threat >= 3 else "bone"
	return pick


## 场上同种存活上限（0 = 不限；和 alive_cap 的全场存活上限是两回事）：普通刷怪抽到已满的种类换成杂兵；投嗣育母的投嗣落地时拟嗣到上限只造成伤害不孵化（run/enemies._brood_land）
func type_cap(kind: String) -> int:
	if D.ENEMIES[kind].has("cap"):
		return int(D.ENEMIES[kind].cap)   # enemies.json 的 cap：场上同种上限（V8 新敌人）
	match kind:
		"stone":
			return 6 if g.t < 180.0 else (8 if g.t < 420.0 else 12)
		"brood", "spitter":
			return 6
		"offspring":
			return 6 if g.t < 420.0 else 10
	return 0


## 场上某一类的存活数：走 enemies_sys 的种类登记（docs/101 S7：原来每次刷怪抽到有上限的种类都扫全表），结果相同
func type_n(kind: String) -> int:
	return g.enemies_sys.type_alive(kind)


func pick_elite() -> String:
	var pool: Array = []
	for k in D.ENEMIES:
		var d: Dictionary = D.ENEMIES[k]
		if d.get("role", "") == "elite" and g.t >= float(d.get("elite_after", 0.0)) and not d.get("no_spawn", false):
			pool.append(k)
	if pool.is_empty():
		return "pocket"
	return pool[g.rng.randi() % pool.size()]


## 最终 Boss 登场时，还没打死的中期 Boss 撤场、不给奖励（用户 9/27，docs/38 B1 ②）：直接移除，不走 kill()（不掉落、不计击杀），
## 顺带取消它的预警；7:00 时两只中期 Boss 共存，不撤
## 中期池第 i 组里有没有和已出场的 Boss 是同一人物（SAME_PERSON）
func person_used(i: int) -> bool:
	var used := {}
	for u in mid_used:
		for t in D.MID_POOL[u]:
			if SAME_PERSON.has(t):
				used[SAME_PERSON[t]] = true
	for t in D.MID_POOL[i]:
		if SAME_PERSON.has(t) and used.has(SAME_PERSON[t]):
			return true
	return false


func retreat_mid_bosses() -> void:
	for b in g.bosses:
		if b.dead:
			continue
		b.retreated = true
		b.dead = true
		g.warns = g.warns.filter(func(w): return not is_same(w.owner, b))
		g.fx.append({"kind": "ring", "pos": b.pos, "r": b.r * 2.0, "life": 0.6, "max": 0.6, "col": Color(0.6, 0.7, 0.9)})
		g.vfx.add_text(b.pos + Vector2(0, -b.r - 30.0), "%s 撤离" % b.name, Color(0.75, 0.8, 0.95), 16)


## 最终 Boss 登场：冻结场地（半径 enemies.json 的 arena_r，缺省 boss/arena_r 520），已有的自然溟痕在 20 秒内退潮（docs/38 §1.7）
func enter_arena(type: String) -> void:
	g.combat.freeze_zone(float(D.ENEMIES.get(type, {}).get("arena_r", Bal.v("boss/arena_r", 520.0))))
	for m in g.mires:
		if not m.get("boss", false):
			m.life = minf(m.life, 20.0)


## 后期词条（用户 9/29「后期小怪太容易被秒」，数值旋钮，缺省 enemy/affix_start = 永不 = 关）：普通怪（非精英 / Boss / 固定 / 箱子）
## 刷出时按概率带一条词条，概率从 affix_start 秒起线性涨到 affix_start + affix_ramp 秒时的 affix_max。两种各半：
##   甲壳 armor：非真实伤害 ×affix_armor（写进 e.def）；潮盾 shield：额外护盾 = 最大生命 × affix_shield，先扣盾（combat.damage）
func roll_affix(e: Dictionary) -> void:
	var st: float = g.combat.enemy_knob("affix_start", 1.0e9)
	if g.t < st or e.elite or e.boss or e.chest or e.ai == "static":
		return
	var p: float = g.combat.enemy_knob("affix_max", 0.35) * clampf((g.t - st) / maxf(1.0, Bal.v("enemy/affix_ramp", 180.0)), 0.0, 1.0)
	if g.rng.randf() >= p:
		return
	if g.rng.randf() < 0.5:
		e.affix = "armor"
		e.def *= Bal.v("enemy/affix_armor", 0.75)
	else:
		e.affix = "shield"
		e.shield_hp = e.maxhp * Bal.v("enemy/affix_shield", 0.30)


## 活着的非 Boss 敌人数（不算宝箱 / 友方单位，如伊莎玛拉的泪滴）
func mob_count() -> int:
	var n := 0
	for e in g.enemies:
		if not e.dead and not e.boss and not e.get("chest", false) and not e.get("friendly", false):
			n += 1
	return n


## 同屏敌人上限：enemy/max_alive（缺省 450）；真人选低画质时 enemy/max_alive_low（300）。
## 机器人 / 自动测试一律用 450——上限会改玩法，批跑数据不能受玩家设置影响
func max_alive() -> int:
	if Cfg.quality == "low" and g.mode == g.Mode.PLAY:
		return dens_cap(int(Bal.v("enemy/max_alive_low", 300.0)))
	return dens_cap(int(Bal.v("enemy/max_alive", float(MAX_ENEMIES))))


## Boss 在场时还能刷几只普通怪：最终 Boss 读 boss/final_mob_cap（120），中期 Boss 读 boss/mid_mob_cap（160，协调人 9/30 定：
## Ⅷ 7:00 双体战全场 230 只、主教 on_boss 0%）；没有 Boss 或上限为 0 时按同屏上限 max_alive()
func boss_mob_room() -> int:
	var cap := 0
	if g.final_boss != null and not g.final_boss.dead:
		cap = int(Bal.v("boss/final_mob_cap", 120.0))
		if trickling() and final_knob("trickle_cap") > 0.0:
			cap = int(final_knob("trickle_cap"))   # 少量补怪的存活杂兵上限（final/trickle_cap）
	elif boss_alive():
		cap = int(Bal.v("boss/mid_mob_cap", 160.0))
	return dens_cap(cap) - mob_count() if cap > 0 else max_alive()   # 存活杂兵上限按怪物密度同比缩


## 最终 Boss 战停刷（用户 10-11「最终 boss 出现以后小怪就可以不用刷了」，docs/38 §8.14）：旋钮 final/<key>，难度表 final_<key> ≥ 0 时优先。
## 代码缺省 0 = 关 = 旧行为（balance.json 里 stop_mobs 填 1）
func final_knob(key: String, def := 0.0) -> float:
	var v := float(g.dmod.get("final_" + key, -1.0))
	return v if v >= 0.0 else Bal.v("final/" + key, def)


## 最终 Boss 在场且 final/stop_mobs 开：普通刷怪 / 精英 / 大群 / 威胁上升的新种类都不刷；Boss 召唤物、剧本刷怪（伊莎玛拉练习靶、
## 子代蜕变等）、补给箱、灯标、商人照常——那些不走这几条路径
func mobs_stopped() -> bool:
	return g.final_boss != null and not g.final_boss.dead and final_knob("stop_mobs") > 0.0


## 最终 Boss 战少量补怪（用户 10-12「最后 boss 还是需要刷新点小怪的，但是频率和数量可以下降点」「新怪中也可以有，可以少一点」，docs/38 §8.14）：
## 停刷开着且 final/trickle_mult > 0 时，普通刷怪按「正常刷怪率 × trickle_mult」继续（替代 enemy/spawn_boss_mult），存活杂兵上限改读
## final/trickle_cap；本级威胁新种类在补怪里的抽取权重 × final/trickle_fresh_w。精英 / 大群 / 威胁上升那一小波仍按 mobs_stopped() 不刷。
## trickle_mult 0（代码缺省）= 10-11 的全停
func trickling() -> bool:
	return mobs_stopped() and final_knob("trickle_mult") > 0.0


## 最终 Boss 登场时 final/clear_mobs_s > 0：场上现有的普通杂兵（不含 Boss / 宝箱 / 友方 / 事件物件）在 N 秒内由远到近逐只消散。
## 消散不算击杀：不掉经验 / 灯油 / 道具、不触发击杀类藏品与干员被动、不计 kills（理由见 docs/38 §8.14）。不掷随机数
func queue_clear(dur: float) -> void:
	var mobs: Array = []
	for e in g.enemies:
		if not e.dead and not e.boss and not e.get("chest", false) and not e.get("friendly", false) and str(e.get("event", "")) == "":
			mobs.append(e)
	mobs.sort_custom(func(a, b): return a.pos.distance_squared_to(g.ppos) > b.pos.distance_squared_to(g.ppos))
	var n := mobs.size()
	for k in n:
		fading.append([mobs[k], g.t + dur * float(k + 1) / float(n)])


func _update_fading() -> void:
	var keep: Array = []
	for f in fading:
		var e: Dictionary = f[0]
		if e.dead:
			continue
		if g.t < float(f[1]):
			keep.append(f)
			continue
		e.dead = true
		g.warns = g.warns.filter(func(w): return not is_same(w.owner, e))
		if not g.vfx.fx_sprite("fx_death_dissolve", e.pos, g.PX * maxf(1.0, e.r / 12.0)):
			g.vfx.anim("fx_death", e.pos, 0.3, g.PX * maxf(1.0, e.r / 12.0))
	fading = keep


func boss_alive() -> bool:
	for b in g.bosses:
		if not b.dead:
			return true
	return false


func update(dt: float) -> void:
	# Boss 按时间登场
	if boss_idx < D.BOSS_TIMES.size() and g.t >= D.BOSS_TIMES[boss_idx]:
		boss_idx += 1
		var group: Array = []
		if boss_idx == D.BOSS_TIMES.size():
			# 测试开关（仅开发版，Cfg.dev_args；发布版屏蔽）：--forceending=<结局> 指定最终 Boss（standard 泡影 / deep 伊莎玛拉 / knight 骑士 / resolve 伊祖米克）
			for a in Cfg.dev_args():
				if a.begins_with("--forceending=") and D.ENDINGS.has(a.substr(14)):
					g.ending = a.substr(14)
			group = [D.ENDINGS[g.ending].boss]
		else:
			var pool: Array = []
			for i in D.MID_POOL.size():
				if not mid_used.has(i) and (boss_idx != 1 or D.MID_FIRST.is_empty() or D.MID_FIRST.has(i)) and not person_used(i):
					pool.append(i)
			var pick: int = pool[g.rng.randi() % pool.size()]
			if g.force_boss >= 0 and not mid_used.has(g.force_boss):
				pick = g.force_boss
			# 测试开关（仅开发版）：--forceboss2=<MID_POOL 下标> 指定第二个（7:00）中期 Boss，例如 3 = 主教 + 蔑视体、4 = 主教 + 斥亡者
			for a in Cfg.dev_args():
				if a.begins_with("--forceboss2=") and boss_idx == 2 and not mid_used.has(int(a.substr(13))):
					pick = int(a.substr(13))
			mid_used.append(pick)
			group = D.MID_POOL[pick]
		var base := edge_pos()
		if g.zone_state != 0 and base.distance_to(g.zone_c) > g.zone_r - 90.0:
			base = g.zone_c + (base - g.zone_c).normalized() * maxf(60.0, g.zone_r - 110.0)
		if boss_idx == D.BOSS_TIMES.size() and group == ["knight_boss"]:
			# 结局二：骑士（已入潮或仍在）重生为最终 Boss，从黑潮中心出现（take_over 返回位置）；若骑士已不在，则从边缘出现
			if g.knight.alive or g.knight.submerged:
				base = g.knight.take_over()
				g.camera_glance(base)   # 镜头一瞥黑潮中心看寒冰重生（用户 10-14；只动镜头，game.camera_glance）
			g.vfx.show_banner("寒冰重生 —— 最后的骑士")
		if boss_idx == D.BOSS_TIMES.size():
			final_at = g.t
			retreat_mid_bosses()
			enter_arena(group[0])
			base = g.combat.arena_clamp(base, 80.0)   # 场地内、离圈边 ≥80 登场
		var spawned: Array = []
		for k in group.size():
			var b := spawn_enemy(group[k], base + Vector2(k * 90.0, 0))
			# 最终 Boss 标记在加进 bosses、跑第一次 AI 之前就设好（docs/38 B0 第 9 项）
			if k == 0 and boss_idx == D.BOSS_TIMES.size():
				g.final_boss = b
			g.bosses.append(b)
			spawned.append(b)
			g.boss = b
		if boss_idx == D.BOSS_TIMES.size() and mobs_stopped() and final_knob("clear_mobs_s") > 0.0:
			queue_clear(final_knob("clear_mobs_s"))
		if spawned.size() == 2:
			spawned[0].partner = spawned[1]
			spawned[1].partner = spawned[0]
		var names: Array = []
		for g_item in group:
			names.append(D.ENEMIES[g_item].name)
		g.vfx.show_banner("%s 出现了" % " 与 ".join(names))
		Sfx.play("roar", 2.0, 0.7, 0.0)
		Sfx.play_overlay("boss_in")
		g.boss_intro.on_spawn(spawned)   # 登场演出（纯覆盖层；无头批跑 / 设置关时不跑，不碰 g.rng）
		g.vfx.shake_screen(1.2)
	# 威胁等级上升：横幅 + 刷一小波新种类
	if g.threat < D.THREAT.size() - 1 and g.t >= D.THREAT[g.threat + 1].t:
		g.threat += 1
		var tr: Dictionary = D.THREAT[g.threat]
		g.vfx.show_banner("威胁上升 · %s —— 新的海嗣浮现" % tr.name)
		Sfx.play("roar", -1.0, 0.75, 0.0)
		g.vfx.shake_screen(0.8)
		var fresh: Array = tr.pool.filter(func(x): return not D.THREAT[g.threat - 1].pool.has(x))
		if not fresh.is_empty() and not mobs_stopped():
			_norm = true
			for k in dens_count(6, "threat"):   # 只数 × 怪物密度（累计余数取整）
				spawn_enemy(fresh[k % fresh.size()], edge_pos())
			_norm = false
	# 刷怪率：spawn_knee 之后按 spawn_late_div 放缓（docs/46 §1.4；缺省拐点在无穷远，行为不变）
	var sp_div: float = Bal.v("enemy/spawn_div", 30.0)
	var sp_knee: float = Bal.v("enemy/spawn_knee", 1.0e9)
	var rate := Bal.v("enemy/spawn_base", 1.6) + minf(g.t, sp_knee) / sp_div + maxf(g.t - sp_knee, 0.0) / Bal.v("enemy/spawn_late_div", sp_div)
	# Boss 在场 / 灯火不足时的刷怪倍率（balance.json enemy 段，docs/38 B0 第 11 项；现值 0.8 / 1.15）
	# 中期 / 最终 Boss 在场分开两个倍率（缺省都读原来的 spawn_boss_mult）；用户 9/27：中期 Boss 在场时普通刷怪照常，由数值填 mid 1.0
	if boss_alive():
		var fin: bool = g.final_boss != null and not g.final_boss.dead
		if fin and trickling():
			rate *= final_knob("trickle_mult")   # 少量补怪：相对正常刷怪率的倍率
		else:
			rate *= Bal.v("enemy/spawn_boss_mult_final" if fin else "enemy/spawn_boss_mult_mid", Bal.v("enemy/spawn_boss_mult", 0.8))
	if g.lamp < 30.0:
		rate *= Bal.v("enemy/spawn_dark_mult", 1.15)
	var dens := density()
	if dens != 1.0:
		rate *= dens   # 怪物密度：普通刷怪率 × density（spawn_acc 本身就是累计余数）
	spawn_acc += rate * dt
	# Boss 在场时的存活杂兵上限（协调人 9/30 定，最终 boss/final_mob_cap / 中期 boss/mid_mob_cap，0 = 关）：活着的非 Boss 敌人到上限就不再刷普通怪，
	# 现有的不杀；精英、Boss 召唤物照常。杂兵墙挡住干员索敌是伊莎玛拉 / 偏执泡影超时的主因（Boss A/B 9/30）
	var mob_room: int = boss_mob_room()
	var stop := mobs_stopped()   # 最终 Boss 战停刷（final/stop_mobs）：累积照常扣掉，不刷
	var mobs_off := stop and not trickling()   # 少量补怪开着时普通怪仍按低倍率 + 低上限补；精英 / 大群仍看 stop
	if not fading.is_empty():
		_update_fading()
	var cap: int = alive_cap()
	if int(g.t) != _samp_s and g.t >= 420.0 and not Cfg.dev_args().is_empty():
		_samp_s = int(g.t)
		var nc := normal_count()
		q_samp.append(nc)   # 测试统计：7 分钟后每秒一次的普通怪存活数（queue_report 给分布）
		if g.t < 600.0:
			q_samp710.append(nc)   # 7–10 分钟（最终 Boss 之前）单独一组（docs/50 §16 怪物密度）
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		if mob_room <= 0 or mobs_off:
			continue
		mob_room -= 1
		if cap > 0:
			q_t.append(g.t)   # 存活上限开着：普通刷怪先进队，下面按空位依次放出（没到上限时同一帧就放出，次序与原来相同）
		elif g.enemies.size() < max_alive():
			_spawn_mob()
	if cap > 0:
		_release_queue(cap, stop, mobs_off)
	# 精英计时在 Boss 在场时照常走（用户 9/27 撤回 B0 第 8 项的冻结：按时间刷，快慢玩家精英数相同）；
	# 数值留的旋钮 enemy/elite_during_boss：Boss 在场时精英计时的速度（1 = 照常、0 = 冻结、0.5 = 减半）
	if boss_alive():
		next_elite += dt * (1.0 - Bal.v("enemy/elite_during_boss", 1.0))
	if stop and g.t >= next_elite:
		next_elite += D.THREAT[g.threat].elite * float(g.dmod.elite_interval)   # 最终 Boss 战停刷：精英计时照走，不出精英
	elif g.t >= next_elite:
		next_elite += D.THREAT[g.threat].elite * float(g.dmod.elite_interval)
		var et := pick_elite()
		_norm = true   # 精英也吃怪物体型 enemy/scale（不吃密度）
		spawn_enemy(et, edge_pos())
		if g.rfx.rule("resolve_elite") > 0:
			spawn_enemy(pick_elite(), edge_pos())
		var et2 := pick_elite() if g.threat >= 4 else ""
		if et2 != "":
			spawn_enemy(et2, edge_pos())
		_norm = false
		if g.threat >= 4:
			var n1: String = D.ENEMIES[et].name
			var n2: String = D.ENEMIES[et2].name
			g.vfx.show_banner(("两只精英「%s」同时出现！击败它们有概率获得藏品" % n1) if n1 == n2 else ("精英「%s」与「%s」同时出现！击败它们有概率获得藏品" % [n1, n2]))
		else:
			g.vfx.show_banner("精英「%s」出现！击败它有概率获得藏品" % D.ENEMIES[et].name)
		Sfx.play("roar", -3.0)
	# 大群：Boss 在场时顺延，最多顺延 boss/horde_defer_max 秒（数值起点 40），到时照常带 3 秒预警出场（用户 9/27）；
	# Boss 先倒下则按 kill() 的「至少推迟 12 秒」；难度修正 horde_in_boss 时不顺延；9:30 之后不再刷（给最终 Boss 留空间）
	var due: float = g.next_horde
	if boss_alive() and int(g.dmod.horde_in_boss) <= 0:
		due += Bal.v("boss/horde_defer_max", 40.0)
	var horde_ok: bool = g.t < 570.0 and not stop   # 最终 Boss 战停刷时连预警也不出
	if g.t >= due - 3.0 and horde_warned != due and horde_ok:
		horde_warned = due
		g.horde_warn = 3.0
		g.horde_gap = g.rng.randf() * TAU
		Sfx.play("roar", -2.0, 0.55, 0.0)
	if g.t >= due and horde_ok:
		g.next_horde += D.THREAT[g.threat].get("horde_every", 120.0)
		g.horde_warn = 0.0
		g.horde_hit = 1.2
		g.vfx.shake_screen(1.4)
		g.fx.append({"kind": "horde_ring", "pos": g.ppos, "r": 640.0, "life": 0.9, "max": 0.9, "col": Color(0.75, 0.3, 1.0)})
		Sfx.play("roar", 2.0, 0.8, 0.0)
		# 数量：32 → 88（10 分钟），× 难度修正 horde；包围圈留 70° 缺口（预警时的箭头也留出这一侧），给玩家一条突围路线
		var n := int((Bal.v("enemy/horde_base", 24.0) + int(g.t / Bal.v("enemy/horde_div", 9.0))) * float(g.dmod.horde))
		n = dens_count(n, "horde")   # 怪物密度：只数 × density（累计余数取整；在 Boss 余量裁剪之前）
		# Boss 在场时（Ⅷ horde_in_boss 让大群不顺延）超出存活杂兵上限的部分裁掉（协调人 9/30）；没有 Boss 时余量 = 同屏上限 max_alive()，不裁
		n = mini(n, maxi(0, boss_mob_room()))
		var gap_half := deg_to_rad(35.0)
		var span: float = TAU - gap_half * 2.0
		var mix := horde_mix()
		var plan := horde_plan(mix, n)
		_norm = true
		var comp := {}
		for s in plan:
			comp[s.id] = int(comp.get(s.id, 0)) + 1
		var hl := {"t": int(g.t), "n": n, "hp": 0.0, "killed": 0, "t80": -1, "minhp": g.hp, "hp0": g.hp, "mix": str(mix.get("name", "")), "comp": comp}
		g.horde_log.append(hl)
		for s in plan:
			if g.enemies.size() >= max_alive() + 60:
				break
			var ang: float = g.horde_gap + gap_half + span * float(s.u)
			var p := g.ppos + Vector2.from_angle(ang) * (g.rng.randf_range(560.0, 640.0) + float(s.dr))
			var he := spawn_enemy(s.id, p)
			he["horde"] = g.horde_log.size() - 1
			he.dormant = false
			# 群体个体的接触伤害 ×0.7：被包围时不至于两下暴毙，压力来自数量而不是单体
			he.dmg *= 0.7
			hl.hp += he.maxhp
		_norm = false
	# 补给箱
	if g.t >= next_chest:
		next_chest = g.t + g.rng.randf_range(35.0, 50.0)
		var nch := 0
		for e in g.enemies:
			if e.chest and e.get("event", "") == "":
				nch += 1
		if nch < 3:
			spawn_chest(g.ppos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(260.0, 420.0))
	# 溟痕（最终 Boss 场地冻结后停刷自然溟痕，docs/38 §1.7）
	if g.t >= g.next_mire and not g.zone_frozen:
		# 溟痕随时间越来越多、越来越大；缩圈后多出现在圈边
		g.next_mire = g.t + g.map.mire_next_interval(g.t)
		var mp := g.ppos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(160.0, 380.0)
		if g.zone_state != 0 and g.rng.randf() < 0.6:
			var ang := (g.ppos - g.zone_c).angle() + g.rng.randf_range(-0.8, 0.8)
			mp = g.zone_c + Vector2.from_angle(ang) * (g.zone_r - g.rng.randf_range(20.0, 120.0))
		if g.mires.size() < int(g.map.mire_cfg().get("max_count", 24)):
			g.mires.append(g.map.mire_new(mp, g.t, int(g.dmod.mire_permanent) > 0))
	# 商人
	if g.merchant.is_empty() and g.merchant_idx < g.MERCHANT_TIMES.size() and g.t >= g.MERCHANT_TIMES[g.merchant_idx]:
		g.merchant_idx += 1
		g.merchant = {"pos": event_pos(260.0, 320.0, 100.0), "life": 60.0, "near": false, "purchases": 0}
		g.shop_items.clear()
		g.shop_refreshed = false
		g.vfx.show_banner("商人出现了 —— 去找他交易源石锭")
		Sfx.play("relic", -4.0)


## 普通刷怪的一只（原来刷怪循环里的那段，原样搬出来；推迟出场的也走这里，按出场那一刻的威胁等级抽种类）
func _spawn_mob() -> void:
	_norm = true
	var ne := spawn_enemy(pick_type(), edge_pos())
	_norm = false
	n_mob += 1
	# 6 分钟后一部分海嗣直接以进化体出现（数量不变，质量提升）
	if not ne.elite and ne.ai != "static" and g.rng.randf() < D.THREAT[g.threat].get("evo", 0.0) * (2.0 if g.ending == "deep" else 1.0):
		g.enemies_sys.evolve(ne)
	if g.ending == "resolve" and g.t >= 520.0:
		ne.weak = ""


## 同屏普通怪存活上限（docs/50 §15 B，用户 10-14 批准「同屏普通怪存活上限 120」；balance.json enemy/alive_cap，0 = 关 = 原行为）。
## 计入上限的「普通怪」：活着的非 Boss、非精英、非宝箱 / 祭坛、非友方、非事件怪（normal_count）；大群、威胁上升那一小波、Boss 召唤、
## 分裂 / 剧本刷怪照算进存活数，但它们自己不排队、照原时机出（包围圈、招式、剧本要完整）。
## 到上限时不删怪：普通刷怪（刷怪率累积出的每一只）进先进先出队列，有空位（normal_count < 上限）时按先后放出；排满 enemy/alive_cap_wait 秒
## （缺省 10）的不再等空位、直接出（保底：后期击杀速度跟不上刷怪率时，硬上限的队列会越排越长、永远排不完，见 docs/50 §15）。
## 种类 / 位置 / 进化在放出那一刻按原来的同一段代码抽，经验 / 掉落随怪本身。没到上限时同一帧进队同一帧放出，随机数次序与原来相同。
## 原来就会「不刷」的两种情况照旧作废、不排队：Boss 在场的存活杂兵余量（boss_mob_room）用完、全场到 max_alive（计入 drop_room）；
## 最终 Boss 停刷（final/stop_mobs）时，登场前还在排队的那些按停刷的规则作废（停刷本来就把累积扣掉不刷），计入 drop_final
var final_at := -1.0
var q_t := PackedFloat64Array()   # 排队中的普通刷怪：进队时的游戏时间（先进先出）
var n_mob := 0                    # 普通刷怪实际刷出的只数（含推迟后放出的）
var q_stat := {"queued": 0, "deferred": 0, "wait_sum": 0.0, "wait_max": 0.0, "q_peak": 0, "drop_final": 0, "drop_room": 0, "forced": 0}
var q_waits := PackedFloat32Array()   # 每只推迟出场的等待秒数（只在测试参数下记，用于分布）
var q_samp := PackedInt32Array()
var q_samp710 := PackedInt32Array()
var _samp_s := -1


func alive_cap() -> int:
	return int(Bal.v("enemy/alive_cap", 0.0))


## 排队保底（enemy/alive_cap_wait 秒，0 = 不保底）：排满这么久的普通刷怪不再等空位，直接出（可短暂超过上限）
func alive_cap_wait() -> float:
	return Bal.v("enemy/alive_cap_wait", 0.0)


func normal_count() -> int:
	var n := 0
	for e in g.enemies:
		if not e.dead and not e.boss and not e.get("elite", false) and not e.get("chest", false) and not e.get("friendly", false) and str(e.get("event", "")) == "":
			n += 1
	return n


func _release_queue(cap: int, stop: bool, mobs_off: bool) -> void:
	if q_t.is_empty():
		return
	if stop:
		# 最终 Boss 停刷：登场前排的队作废（少量补怪开着时，登场后新进队的照常按补怪上限放）
		var k := 0
		while k < q_t.size() and (mobs_off or q_t[k] < final_at):
			k += 1
		if k > 0:
			q_stat.drop_final += k
			q_t = q_t.slice(k)
		if q_t.is_empty():
			return
	if q_t.size() > int(q_stat.q_peak):
		q_stat.q_peak = q_t.size()
	var nn: int = normal_count()
	var k2 := 0
	var rec: bool = not Cfg.dev_args().is_empty()
	var wmax: float = alive_cap_wait()
	# 有空位就按先后放；排满 wmax 秒的不再等空位（保底：推迟有上限，不会一直排不进去，刷出总数与经验掉落不丢）
	# Boss 在场的存活杂兵余量（boss_mob_room）/ 全场 max_alive 挡住的照原规则作废（原来这两种情况就是不刷），只有存活上限是推迟
	var room: int = boss_mob_room()
	while k2 < q_t.size() and (nn < cap or (wmax > 0.0 and g.t - q_t[k2] >= wmax)):
		var w: float = g.t - q_t[k2]
		k2 += 1
		if room <= 0 or g.enemies.size() >= max_alive():
			q_stat.drop_room += 1
			continue
		if nn >= cap:
			q_stat.forced += 1
		room -= 1
		nn += 1
		q_stat.queued += 1
		if w > 0.0:
			q_stat.deferred += 1
			q_stat.wait_sum += w
			q_stat.wait_max = maxf(float(q_stat.wait_max), w)
			if rec:
				q_waits.append(w)
		_spawn_mob()
	if k2 > 0:
		q_t = q_t.slice(k2)


## 刷怪队列统计（--balance 结束时 autotest 打 SPAWNQ 行）：放出 / 推迟只数、等待分布、队列峰值、结束时还在排的
func queue_report() -> Dictionary:
	var w: Array = Array(q_waits)
	w.sort()
	var pc := func(q: float) -> float: return snappedf(float(w[mini(w.size() - 1, int(q * (w.size() - 1) + 0.5))]), 0.01) if not w.is_empty() else 0.0
	var hist := {"<1s": 0, "1-3s": 0, "3-10s": 0, "10-30s": 0, ">=30s": 0}
	for x in w:
		var b: String = "<1s" if x < 1.0 else ("1-3s" if x < 3.0 else ("3-10s" if x < 10.0 else ("10-30s" if x < 30.0 else ">=30s")))
		hist[b] += 1
	return {"cap": alive_cap(), "spawned": n_mob, "queued": q_stat.queued, "deferred": q_stat.deferred, "pending_end": q_t.size(),
		"q_peak": q_stat.q_peak, "drop_final": q_stat.drop_final, "drop_room": q_stat.drop_room, "forced": q_stat.forced, "wait_cap": alive_cap_wait(), "wait_mean": snappedf(float(q_stat.wait_sum) / maxf(1.0, float(q_stat.deferred)), 0.01),
		"alive_420_med": _pct_i(q_samp, 0.5), "alive_420_p95": _pct_i(q_samp, 0.95), "alive_420_max": _pct_i(q_samp, 1.0),
		"density": density(), "alive_710_med": _pct_i(q_samp710, 0.5), "alive_710_p95": _pct_i(q_samp710, 0.95), "alive_710_max": _pct_i(q_samp710, 1.0),
		"wait_p50": pc.call(0.5), "wait_p90": pc.call(0.9), "wait_p99": pc.call(0.99), "wait_max": snappedf(float(q_stat.wait_max), 0.01), "hist": hist}


func _pct_i(a: PackedInt32Array, q: float) -> int:
	if a.is_empty():
		return 0
	var b: Array = Array(a)
	b.sort()
	return int(b[mini(b.size() - 1, int(q * (b.size() - 1) + 0.5))])


## 是不是结局的最终 Boss（偏执泡影 / 最后的骑士 / 伊莎玛拉 / 伊祖米克，按 waves.json 的结局表）；其余 Boss 都是中期 Boss
func is_final_boss_type(type: String) -> bool:
	for k in D.ENDINGS:
		if str(D.ENDINGS[k].get("boss", "")) == type:
			return true
	return false


func new_enemy(type: String, pos: Vector2) -> Dictionary:
	var d: Dictionary = D.ENEMIES[type]
	var role: String = d.get("role", "")
	g.ensure_enemy_tex(d.tex)   # 网页版推迟加载的贴图在这里补读（桌面版名单为空，直接返回）；要在下面查 tex_* 变体之前

	# 生命曲线：前 8 分钟线性到 ×4.4，之后放缓（后期靠进化体与远程比例提升压力，而不是堆血）
	# 曲线参数见 data/balance.json enemy 段（docs/27 §4）
	var hpm := g.combat.enemy_hp_time_mult() * float(g.dmod.enemy_hp)
	# 最终 Boss 在场时新刷的杂兵（含大群、Boss 召唤物）改用 dmod.boss_fight_enemy_hp（-1 = 跟 enemy_hp 走）；已在场的不回溯改血
	# （docs/38 §8.5：Ⅷ 杂兵血 ×1.7 把干员输出吸走，泡影 on_boss 只有标准档的 1/3）
	var bf: float = g.combat.enemy_knob("boss_fight_enemy_hp", -1.0)   # difficulty/<档>/ 优先，其次 enemy/boss_fight_enemy_hp
	if bf >= 0.0 and role != "boss" and g.final_boss != null and not g.final_boss.dead:
		hpm = g.combat.enemy_hp_time_mult() * bf
	var dmm := float(g.dmod.enemy_dmg)
	var dmg_t := 1.0 + minf(g.t, Bal.v("enemy/dmg_knee", 480.0)) / Bal.v("enemy/dmg_div", 260.0)
	# 前期敌人伤害加成（用户 9/27 前 3 分钟方案 A，数值旋钮，缺省 1.0 = 不变）：开局 ×enemy/dmg_early，到 enemy/dmg_early_until 秒线性回到 ×1。
	# 只作用于普通怪和精英（Boss 在下面另算 e.dmg，不吃 dmg_t）；敌弹、抛石、冲击环、自爆、预警招式都按 e.dmg 算，自动跟上
	dmg_t *= lerpf(Bal.v("enemy/dmg_early", 1.0), 1.0, clampf(g.t / maxf(1.0, Bal.v("enemy/dmg_early_until", 240.0)), 0.0, 1.0))
	# 后期敌人伤害（用户 10-01「后期怪物攻击力轻微上调」，数值方案 a）：dmg_late_start 秒起，按 dmg_late_div 秒涨 1.0 的斜率叠加，最多 +dmg_late_cap。
	# dmg_late_cap 可按难度档覆盖（difficulty/<档>/dmg_late_cap，-1 = 跟 enemy 段）；代码缺省 0 = 现行为
	var late_cap: float = g.combat.enemy_knob("dmg_late_cap", 0.0)
	if late_cap > 0.0:
		dmg_t += minf(maxf(g.t - Bal.v("enemy/dmg_late_start", 420.0), 0.0) / maxf(1.0, Bal.v("enemy/dmg_late_div", 900.0)), late_cap)
	next_id += 1
	var e := {
		"id": next_id, "type": type, "name": d.name, "tex": d.tex, "pos": pos,
		"hp": d.hp * hpm * g.enemy_hp_mult, "maxhp": d.hp * hpm * g.enemy_hp_mult,
		"spd": d.spd * g.rng.randf_range(0.9, 1.1) * D.THREAT[g.threat].get("spd", 1.0), "dmg": d.dmg * dmg_t * dmm * g.enemy_dmg_mult,
		"r": d.r, "r0": d.r, "xp": d.xp, "age": 0.0,
		"evo": false, "elite": role == "elite", "boss": role == "boss", "stun": 0.0,
		"kb": Vector2.ZERO, "flash": 0.0, "squash": 0.0, "slow": 0.0, "jhit": 0.0, "dead": false, "bt": 0.0, "fx": 1.0,
		"ai": d.ai, "range": d.get("range", 0.0), "cd": d.get("cd", 0.0) * g.enemy_cd_mult, "cdt": g.rng.randf() * d.get("cd", 1.0),
		"frost": d.get("frost", 0.0), "corrode": d.get("corrode", 0.0), "nerve": d.get("nerve", 0.0), "def": float(d.get("armor", 1.0)), "set_t": 0.0, "set_done": false,
		"chest": false, "hidden": false, "invuln": false, "friendly": false, "hits": 0, "phase": 1, "charge": 0.0, "feed": false,
		# 状态字段统一在此初始化（Boss 招式 / 假死 / 冲刺 / 流血），避免各处 get() 默认值不一致
		"coma": false, "wind": 0.0, "pose": 0.0, "pose_max": 0.0, "haste": 0.0, "air": 0.0, "channel": 0.0,
		"dash_t": 0.0, "dash_w": 0.0, "nova_w": 0.0, "burst_w": 0.0, "burst_cd": 0.0, "bleed": 0.0, "bleed_t": 0.0, "mv_until": 0.0, "dpos": pos,
		# 贴图变体在生成时查一次，绘制时不再每帧拼字符串
		"tex_move": g.tex.get(d.tex + "_move") != null, "tex_feign": g.tex.get(d.tex + "_feign") != null, "tex_attack": g.tex.get(d.tex + "_attack") != null,
		"tex_charge": g.tex.get(d.tex + "_charge") != null, "tex_death": g.tex.get(d.tex + "_death") != null,
		"weak": d.get("weak", ""),
		"aggro": Vector2.INF, "corr_t": 0.0, "corr_dmg": 0.0,
		# V8 新敌人（enemy_ai.gd）：自爆鼓胀 / 休眠与唤醒 / 狂暴与铺痕 / 光环计时 / 小怪攻击帧条
		"blast_w": 0.0, "dormant": bool(d.get("dormant", false)), "wake_t": 0.0, "enraged": false, "trail_t": 0.0, "aura_t": 0.0, "atk_until": 0.0,
		"affix": "", "shield_hp": 0.0,   # 后期词条（甲壳 / 潮盾，roll_affix）
		"extra_next": g.t + float(d.get("extra", {}).get("first_delay", 3.0)) + (float(next_id % 5) * 0.1 if d.get("extra", {}).has("first_delay") else float(next_id % 7) * 0.43),
	}
	roll_affix(e)
	if tmpl_keys.is_empty():
		tmpl_keys = e.keys()   # 字段模板（check_enemy 用）：取字面量本身，不含下面按类型追加的字段
	if _norm and role == "" and density() != 1.0:
		_dens_apply(e)
	if _norm and (role == "" or role == "elite") and escale() != 1.0:
		e.r *= escale()   # 怪物体型：判定半径 × scale，r0 不动，画面缩放 enemy_scale = PX × r / r0 跟着放大
		e["sc"] = escale()
	if e.elite:
		e.hp *= Bal.v("enemy/elite_hp_mult", 7.0)
		e.maxhp = e.hp
		e.xp *= Bal.v("enemy/elite_xp_mult", 10.0)
		e.dmg *= Bal.v("enemy/elite_dmg_mult", 1.3)
	if e.boss:
		# Boss 吃削血藏品（镶金骨骰 / 黑夜呢喃 / 大静谧）最多 -20%（docs/42 §3.3：原来全额生效，2 件以上时 Boss 9 秒被秒）
		e.hp = d.hp * (1.0 + g.t / Bal.v("enemy/boss_hp_time_div", 600.0)) * float(g.dmod.boss_hp) * maxf(Bal.v("boss/hp_mult_floor", 0.8), g.enemy_hp_mult)
		# Boss 血量旋钮（数值会话在 balance.json 的 boss 段填）：中期 / 最终各一个总倍率，另有每只 Boss 单独的倍率；缺省都是 1.0
		e.hp *= Bal.v("boss/hp_final" if is_final_boss_type(type) else "boss/hp_mid", 1.0) * Bal.v("boss/hp_x_" + type, 1.0)
		if is_final_boss_type(type):
			e.hp *= float(g.dmod.get("final_boss_hp", 1.0))   # 按档只加最终 Boss 的血（停刷补偿，docs/38 §8.14；缺省 1.0）
		e.maxhp = e.hp
		e.spd = d.spd
		e.dmg = d.dmg * dmm * float(g.dmod.boss_dmg) * g.enemy_dmg_mult
		g.combat.gate_init(e, type)   # 阶段卡点与每幕最短时长（docs/38 §1.3）
	if type == "pocket":
		e.burst_at = e.maxhp * 0.85
	if type == "ishar":
		e.friendly = true
		e.invuln = true
	if type == "izumik":
		e.hp = e.maxhp * 0.35
		e.invuln = true
	if d.has("ammo"):
		e.ammo = d.ammo
		e.reload_t = 20.0
		e.channel = 0.0
	return e


## 怪物密度（docs/50 §16，用户 10-14「提高怪物血量和数值，削减同屏数量」「60只左右是不是比较合理的上限」，性能试验）：
## balance.json enemy/density = k（缺省 1.0 = 原行为，同 seed 逐行相同）。k < 1 时：
##   只数：普通刷怪率、大群只数、威胁上升那一小波只数 × k（后两者用各自的累计余数取整，不耗 g.rng）；
##         同屏 / Boss 在场的存活杂兵上限（max_alive、boss/final_mob_cap、mid_mob_cap、final/trickle_cap）与同种上限（pick_type 的 caps）同比 × k；
##   单只（只对这三条路径刷出的普通怪，role 为空；精英 / Boss / 事件 / 剧本 / Boss 召唤 / 友方不动）：生命、潮盾、经验 ÷ k，
##         接触 / 子弹 / 招式伤害（都从 e.dmg 算）÷ k^density_dmg_exp（缺省 1）；e.dk = 1/k 记在敌人上，
##         击杀时灯油量、磁铁 / 回复药剂掉率、部件削血、击杀回复 / 252 的击杀权重按 dk 放大（combat.kill、relic_fx.on_kill），总量期望不变。
##   体型、速度、画面、击退 / 控制都不变。
## 怪物体型（docs/50 §16，用户 10-14「普通小怪能不能大一点」）：enemy/scale = s（缺省 1.0 = 不变）。上面三条普通刷怪路径、精英刷怪（含箱形恐鱼现形）
## 刷出的普通怪 / 精英：判定半径 e.r × s（受击 / 接触 / 分离 / 吞噬都按 e.r），e.r0 不动，所以两条绘制路径（缓存 / 原路径）的缩放 PX × r / r0 同步 × s；
## 影子、头顶标记、弱点、击杀爆点、溶解都按 e.r 走；e.sc = s 记在敌人上（死亡帧条按它放大、击杀顿帧 / 音高按原体型判）。Boss / 召唤物 / 友方 / 事件不动
var _norm := false      # 本次 spawn_enemy 是不是普通刷怪 / 大群 / 威胁上升小波 / 精英刷怪（密度只对其中 role 为空的普通怪，体型对普通怪与精英）
var _dacc := {}         # 各渠道的累计余数（"horde" / "threat"）


func density() -> float:
	return Bal.v("enemy/density", 1.0)


func escale() -> float:
	return Bal.v("enemy/scale", 1.0)


## 只数 × 密度，按渠道累计余数取整（density 1 时原样返回）
func dens_count(n: int, ch: String) -> int:
	var k := density()
	if k == 1.0:
		return n
	var f: float = float(n) * k + float(_dacc.get(ch, 0.0))
	var m := int(floor(f))
	_dacc[ch] = f - float(m)
	return m


## 上限 × 密度（四舍五入，至少 1；density 1 时原样返回）
func dens_cap(c: int) -> int:
	var k := density()
	if k == 1.0 or c <= 0:
		return c
	return maxi(1, roundi(float(c) * k))


func _dens_apply(e: Dictionary) -> void:
	var inv := 1.0 / density()
	# 单只生命 × (1/k)^density_hp_exp（缺省 1 = 总血量池不变；< 1 = 单只更薄、总血量池 × k^(1−exp)，用户 10-14「普通小怪 1–2 下打死」，docs/50 §16.9）
	var hpm: float = pow(inv, Bal.v("enemy/density_hp_exp", 1.0))
	e.hp *= hpm
	e.maxhp *= hpm
	e.shield_hp *= hpm
	e.xp *= inv
	e.dmg *= pow(inv, Bal.v("enemy/density_dmg_exp", 1.0))
	e["dk"] = inv


## 本次大群的编成（data/waves.json，EA 1.1 大群混编）：威胁等级写了 horde_mix 就从中随机抽一套（g.rng，同 seed 可复现），
## 和上一次大群同名时换下一套，不连着来两次一样的；没写就沿用旧格式 horde（主体列表）。
## 编成 = body 主体（按列表循环填满）+ extra 特种（远程 / 冲锋 / 坦克按比例混入）
func horde_mix() -> Dictionary:
	var tr: Dictionary = D.THREAT[g.threat]
	var mixes: Array = tr.get("horde_mix", [])
	if mixes.is_empty():
		return {"name": "", "body": tr.horde, "extra": []}
	var i := g.rng.randi() % mixes.size()
	if mixes.size() > 1 and not g.horde_log.is_empty() and str(g.horde_log[g.horde_log.size() - 1].get("mix", "")) == str(mixes[i].name):
		i = (i + 1) % mixes.size()
	return mixes[i]


## 把编成展开成 n 个刷怪位 {id, u 包围圈上的位置 0–1, dr 半径偏移}。特种先排（刷怪上限截断时先截主体）。
## extra 每项：id、pct 占总数比例（四舍五入后夹在 min–max）、at 站位：
##   ring 沿整圈均匀分布 / back 均匀分布且靠后 90（远程站后排）/ front 靠前 70（慢速坦克顶在前面）/ pack 挤在一段弧上成群冲来
## 特种合计最多占一半，主体至少一半，保证「大群」仍是一大群
func horde_plan(mix: Dictionary, n: int) -> Array:
	var out: Array = []
	var body: Array = mix.get("body", D.THREAT[g.threat].horde)
	var room := n / 2
	var ei := 0
	for ex in mix.get("extra", []):
		var k := clampi(roundi(n * float(ex.get("pct", 0.0))), int(ex.get("min", 0)), int(ex.get("max", 99)))
		k = mini(k, room)
		room -= k
		var at: String = ex.get("at", "ring")
		var dr := {"back": 90.0, "front": -70.0}.get(at, 0.0) as float
		# 不同特种错开一点角度，免得和上一种叠在同一个方位
		var off := 0.37 * ei
		var pc := g.rng.randf_range(0.15, 0.85) if at == "pack" else 0.0
		for j in k:
			var u: float
			if at == "pack":
				u = clampf(pc + (j - (k - 1) * 0.5) * 0.025, 0.0, 1.0)
			else:
				u = fposmod((j + 0.5 + off) / k, 1.0)
			out.append({"id": ex.id, "u": u, "dr": dr})
		ei += 1
	var nb := n - out.size()
	for i in nb:
		out.append({"id": body[i % body.size()], "u": (i + 0.5) / nb, "dr": 0.0})
	return out


func spawn_enemy(type: String, pos: Vector2) -> Dictionary:
	var e := new_enemy(type, pos)
	# 休眠的敌人（钵海收割者）从屏幕外刷出来就看不到了：改放到主控周围 330–480 的海床上当伏兵；大群里的会在刷出后唤醒
	if e.dormant and pos.distance_to(g.ppos) > 700.0:
		e.pos = g.map.push_out(g.ppos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(330.0, 480.0), e.r)
	g.enemies.append(e)
	check_enemy(e, type)
	return e


## 敌人字典字段校验（2026-09-26，docs/39）：以 new_enemy 的字段为模板，测试运行（带 --xxx 参数）时检查每个加入 g.enemies 的字典；
## 缺字段直接 assert 失败（快检记为 SCRIPT ERROR）。另起炉灶拼敌人字典的地方（如补给箱）最容易漏字段，读到时才报「key 不存在」。
## 导出的正式版不执行 assert。模板在第一次正常刷怪时记下，不为此额外生成敌人（会消耗对局随机数）。
var tmpl_keys: Array = []


func check_enemy(e: Dictionary, where: String) -> void:
	if tmpl_keys.is_empty() or Cfg.dev_args().is_empty():
		return
	var miss: Array = tmpl_keys.filter(func(k): return not e.has(k))
	assert(miss.is_empty(), "敌人字典缺字段（%s）：%s" % [where, ", ".join(miss)])


## 补给箱；约 15% 是伪装的箱形恐鱼
func spawn_chest(pos: Vector2, event_id := "") -> void:
	next_id += 1
	g.enemies.append({
		"id": next_id, "type": "chest", "name": "补给箱" if event_id == "" else "海嗣祭坛", "tex": "e_chest" if event_id == "" else "e_event", "pos": pos, "hp": 22.0, "maxhp": 22.0,
		"event": event_id,
		"spd": 0.0, "dmg": 0.0, "r": 13.0, "r0": 13.0, "xp": 0.0, "age": 0.0, "evo": false, "elite": false, "boss": false,
		"stun": 0.0, "kb": Vector2.ZERO, "flash": 0.0, "squash": 0.0, "slow": 0.0, "jhit": 0.0, "dead": false, "bt": 0.0, "fx": 1.0,
		"ai": "static", "range": 0.0, "cd": 0.0, "cdt": 0.0, "frost": 0.0, "corrode": 0.0, "nerve": 0.0, "def": 1.0, "set_t": 0.0, "set_done": true,
		"chest": true, "hidden": _mimic_roll(event_id), "invuln": false, "friendly": false, "hits": 0, "phase": 1, "charge": 0.0, "feed": false,
		"coma": false, "wind": 0.0, "pose": 0.0, "pose_max": 0.0, "haste": 0.0, "air": 0.0, "channel": 0.0,
		"dash_t": 0.0, "dash_w": 0.0, "nova_w": 0.0, "burst_w": 0.0, "burst_cd": 0.0, "bleed": 0.0, "bleed_t": 0.0, "mv_until": 0.0, "dpos": pos,
		"tex_move": false, "tex_feign": false, "tex_attack": false, "tex_charge": false, "tex_death": false,
		"weak": "", "aggro": Vector2.INF, "corr_t": 0.0, "corr_dmg": 0.0,   # 与 new_enemy 对齐（check_enemy 查出来的缺口）
		"blast_w": 0.0, "dormant": false, "wake_t": 0.0, "enraged": false, "trail_t": 0.0, "aura_t": 0.0, "atk_until": 0.0,
		"affix": "", "shield_hp": 0.0,
		"extra_next": INF,
	})
	check_enemy(g.enemies[-1], "chest")


## 是否伪装成箱形恐鱼：约 15%；持有补给箱钥匙（docs/57 P17）期间不出。随机数先抽再判断，钥匙不改变 g.rng 的消耗
func _mimic_roll(event_id: String) -> bool:
	if event_id != "":
		return false
	var roll: bool = g.rng.randf() < 0.15
	return roll and g.rfx.rule("chest_keys") <= 0


## 箱形恐鱼现形
func reveal_mimic(e: Dictionary) -> void:
	_norm = true   # 箱形恐鱼现形算精英刷怪（怪物体型）
	var m := new_enemy("mimic", e.pos)
	_norm = false
	for k in m.keys():
		if k != "id":
			e[k] = m[k]
	e.flash = 0.2
	g.vfx.show_banner("箱形恐鱼！")
	g.vfx.add_text(e.pos + Vector2(0, -30), "伪装！", UI.RED, 20)
	Sfx.play("roar", -2.0, 1.3)
	g.vfx.shake_screen(0.6)
	g.vfx.sparks(e.pos, Vector2.ZERO, Color(1.0, 0.8, 0.4), 14, 260.0)
