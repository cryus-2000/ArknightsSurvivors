extends RefCounted
## 敌人的逐帧更新：移动 / 攻击调度（行为细节在 enemies/enemy_ai.gd、Boss 在 boss_ai.gd）、状态与形态变化、敌方抛射物与弹幕；
## 空间网格与索敌查询（query / nearest / arc_hit / densest_point，干员经 characters/op_api.gd 调用）。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json 数值旋钮（docs/27）

const Game = preload("res://scripts/game.gd")
const Native = preload("res://scripts/native/native.gd")   # 原生模块薄封装（docs/101 §4.7）   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
const CELL := 48.0
const EVO_AGE := 35.0   # 进化：存活这么久的普通怪变精英（随时间缩短，见 update）
const EVO_XP := 2.0     # 进化后经验倍率
var mire_tick := 0.0
var nest_tick := 0.0


func _init(game: Game) -> void:
	g = game


var max_r := 0.0   # 本帧网格里最大的敌人半径（build_grid 记；我方子弹命中查询半径 = b.r + max_r，docs/101 §3.4 ⑦）


var _gcell := PackedInt32Array()   # 每个下标 3 个 int：所在格 gx、gy、在不在格里（原生核心照这张表重建同一张网格，docs/101 §4.7）


func build_grid() -> void:
	g.grid.clear()
	var mr := 0.0
	var ne: int = g.enemies.size()
	_gcell.resize(ne * 3)
	for i in ne:
		var e: Dictionary = g.enemies[i]
		_gcell[i * 3 + 2] = 0
		if e.dead or e.get("friendly", false):
			continue
		if e.r > mr:
			mr = e.r
		var k := Vector2i(floori(e.pos.x / CELL), floori(e.pos.y / CELL))
		_gcell[i * 3] = k.x
		_gcell[i * 3 + 1] = k.y
		_gcell[i * 3 + 2] = 1
		if g.grid.has(k):
			g.grid[k].append(i)
		else:
			g.grid[k] = [i]
	max_r = mr


func query(pos: Vector2, radius: float) -> Array:
	var out: Array = []
	var x0 := floori((pos.x - radius) / CELL)
	var x1 := floori((pos.x + radius) / CELL)
	var y0 := floori((pos.y - radius) / CELL)
	var y1 := floori((pos.y + radius) / CELL)
	var n: int = g.enemies.size()
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var cell = g.grid.get(Vector2i(cx, cy))
			if cell == null:
				continue
			# 查询时再判阵营，避免本帧构网之后变为友方的单位继续吸收索敌/子弹。
			# 不用 filter 闭包、不建中间数组（每只敌人每帧都查一次，docs/50 §9.11 ②）
			for j in cell:
				if j >= 0 and j < n and not g.enemies[j].get("friendly", false):
					out.append(j)
	return out


## ---- 热字段平行数组（docs/101 B8、§4.3）：B 运动段只读写这几列。按本帧 g.enemies 下标（0..n-1）排，段首 _hot_gather 读入、段尾
## _hot_scatter 写回；位置 PackedVector2Array（与字典里的 Vector2 同为 float32），半径 / 场地留边 PackedFloat64Array（与 GDScript float 同为 float64），
## 算式与类型照搬原来的字典版，所以结果逐位相同。标志位见 HF_*
const HF_DEAD := 1
const HF_FRIENDLY := 2
const HF_STATIC := 4
const HF_BOSS := 8
const HF_EVO := 16
const HF_ELITE := 32
const HF_CHEST := 64
const HF_FEED := 128
const HF_IZUMIK1 := 256   # 一阶段伊祖米克（子代碰到就被吸收）
var _hp := PackedVector2Array()
var _hr := PackedFloat64Array()
var _hz := PackedFloat64Array()   # Boss 的场地留边（骑士按整个画幅顶角算，其余 = r）
var _hf := PackedInt32Array()


func _hot_gather(n: int) -> void:
	_hp.resize(n)
	_hr.resize(n)
	_hz.resize(n)
	_hf.resize(n)
	for i in n:
		var e: Dictionary = g.enemies[i]
		_hp[i] = e.pos
		_hr[i] = e.r
		var f := 0
		if e.dead:
			f |= HF_DEAD
		if e.get("friendly", false):
			f |= HF_FRIENDLY
		if e.ai == "static":
			f |= HF_STATIC
		if e.boss:
			f |= HF_BOSS
			var margin := float(e.r)
			if e.type == "knight_boss":
				# 骑士按整个画幅的最远顶角留边：含受击横向拉伸30%、上浮14与描边。
				var draw_scale: float = Game.PX * float(D.ENEMIES[e.type].get("draw_scale", 1.0))
				margin = maxf(margin, Vector2(48.0 * draw_scale * 1.3 + 2.0, 80.0 * draw_scale + 16.0).length())
			_hz[i] = margin
		if e.evo:
			f |= HF_EVO
		if e.elite:
			f |= HF_ELITE
		if e.chest:
			f |= HF_CHEST
		if e.feed:
			f |= HF_FEED
		if e.type == "izumik" and e.phase == 1:
			f |= HF_IZUMIK1
		_hf[i] = f


func _hot_scatter(n: int) -> void:
	for i in n:
		if _seg_on[i] != 0:
			g.enemies[i].pos = _hp[i]


## 原生运动核心（ark_native EnemyCore，docs/101 §4.7）：OPT_CPP 置位、没有扩展、或原生报错（景物预查越界）时返回 false，走 GDScript 核心。
## 输入输出与 _motion_core 相同：读写 _hp / _seg_on，登记 _dv_* / _ab_*；景物底座由 map.push_table 按敌人所在范围 ±3 格预先查好
var _pt_empty: Array = [PackedInt32Array(), PackedVector2Array(), PackedFloat64Array()]
var _pt: Array = _pt_empty   # 景物预查表缓存（push_table 的结果）及其键：队长所在格、地图实例
var _pt_cx := 1 << 40
var _pt_cy := 1 << 40
var _pt_map := 0


func _motion_native(n: int, dt: float) -> bool:
	if g.opt_old & Game.OPT_CPP:
		return false
	var core = Native.enemy_core()
	if core == null or n == 0:
		return false
	if _gcell.size() < n * 3:
		return false   # 网格表比本帧敌人少（不该发生：网格在本帧 A 段之前按全表建）
	var grid: PackedInt32Array = _gcell if _gcell.size() == n * 3 else _gcell.slice(0, n * 3)
	var pp: Array = g.map.push_params()   # [on, cell, rx, ry]
	var x0 := 0
	var x1 := -1
	var y0 := 0
	var y1 := -1
	var pt: Array = _pt_empty
	if pp[0]:
		# 预查范围：队长所在格 ±4（会被推出景物的是非 Boss 普通怪：离队长 > 1300 的在 A 段已回收、刷怪落点 720–820，加上 push_out 自身 ±1 格）；
		# 景物是静态的，表按（队长格、地图）缓存，跨格才重建
		var pc: float = pp[1]
		var pcx := floori(g.ppos.x / pc)
		var pcy := floori(g.ppos.y / pc)
		x0 = pcx - 4
		x1 = pcx + 4
		y0 = pcy - 4
		y1 = pcy + 4
		var mid: int = g.map.get_instance_id()
		if pcx != _pt_cx or pcy != _pt_cy or mid != _pt_map:
			_pt_cx = pcx
			_pt_cy = pcy
			_pt_map = mid
			_pt = g.map.push_table(x0, x1, y0, y1)
		pt = _pt
	var params := PackedFloat64Array([dt, CELL, 1.0 if g.zone_state != 0 else 0.0, g.zone_r, g.zone_c.x, g.zone_c.y, float(g.frame_n),
		1.0 if pp[0] else 0.0, pp[1], pp[2], pp[3], x0, x1, y0, y1])
	var res: Array = core.step(_hp, _hr, _hz, _hf, _seg_on, _seg_v, grid, params, pt[0], pt[1], pt[2])
	if int(res[4]) != 0:
		return false
	_hp = res[0]
	_seg_on = res[1]
	var dv: PackedInt32Array = res[2]
	for k in range(0, dv.size(), 2):
		_dv_e.append(dv[k])
		_dv_o.append(dv[k + 1])
	var ab: PackedInt32Array = res[3]
	for k in range(0, ab.size(), 2):
		_ab_e.append(ab[k])
		_ab_o.append(ab[k + 1])
	return true


## 运动核心（将来的 EnemyCore.step；只读写上面的列 + _seg_on / _seg_v，登记吞噬候选 _dv_* 与吸收 _ab_*；不抽随机数、不碰字典）。
## 景物推出 g.map.push_out 仍在循环里按原次序调（原生版要把景物烘成数据，docs/101 §4.2 ①）
func _motion_core(n: int, dt: float) -> void:
	var zone_on: bool = g.zone_state != 0
	var zr: float = g.zone_r
	var zc: Vector2 = g.zone_c
	var fn: int = g.frame_n
	var grid: Dictionary = g.grid
	for i in n:
		if _seg_on[i] == 0:
			continue
		var fi: int = _hf[i]
		if fi & HF_DEAD:   # A 段里被别的单位打死（Boss 招式、持续伤害外的结算）
			_seg_on[i] = 0
			continue
		var p: Vector2 = _hp[i]
		var ri: float = _hr[i]
		var absorbed := false
		# ---- 分离 + 吞噬
		if not (fi & HF_STATIC):
			# 分离：同样的格子顺序、同样的越界与阵营判断；查询范围按进循环前的位置定
			var qr: float = ri + 20.0
			var qp: Vector2 = p
			var x0 := floori((qp.x - qr) / CELL)
			var x1 := floori((qp.x + qr) / CELL)
			var y0 := floori((qp.y - qr) / CELL)
			var y1 := floori((qp.y + qr) / CELL)
			var stop := false
			for cx in range(x0, x1 + 1):
				if stop:
					break
				for cy in range(y0, y1 + 1):
					if stop:
						break
					var cell = grid.get(Vector2i(cx, cy))
					if cell == null:
						continue
					for j in cell:
						if j < 0 or j >= n or j == i:
							continue
						var fj: int = _hf[j]
						if fj & (HF_FRIENDLY | HF_DEAD):
							continue
						var diff: Vector2 = p - _hp[j]
						var d := diff.length()
						var min_d: float = ri + _hr[j]
						if d < min_d and d > 0.01:
							# 吞噬只登记候选（B 段不抽随机数），掷骰在 C 段按这里的次序做；候选照常被推开
							if (fi & HF_EVO) and not (fj & (HF_EVO | HF_ELITE | HF_BOSS | HF_CHEST | HF_STATIC)) and d < ri:
								_dv_e.append(i)
								_dv_o.append(j)
							# 伊祖米克的子代被 Boss 吸收（在 C 段结算；这只本帧不再移动）
							if (fi & HF_FEED) and (fj & HF_IZUMIK1):
								_ab_e.append(i)
								_ab_o.append(j)
								absorbed = true
								stop = true
								break
							if not (fi & HF_BOSS):
								p += diff / d * (min_d - d) * 0.3
			if absorbed:
				_hp[i] = p
				continue
		p += _seg_v[i] * dt
		# 包含普通移动、外来击退和自主冲锋；约束当前可见圈，避免冻结场地圆心过渡时越界。
		if (fi & HF_BOSS) and zone_on:
			var limit := maxf(0.0, zr - _hz[i])
			var offset: Vector2 = p - zc
			if offset.length_squared() > limit * limit:
				p = zc + offset.normalized() * limit
		if not (fi & HF_BOSS) and not (fi & HF_STATIC) and (i + fn) % 2 == 0:
			p = g.map.push_out(p, ri * 0.8)
		_hp[i] = p


## 三段更新的逐帧暂存（docs/101 B7 ③）：A 段算出的本帧速度、是否进入 B / C；B 段登记的吞噬候选（捕食者 i、猎物 j）与伊祖米克吸收（子代 i、Boss j）
var _seg_v := PackedVector2Array()
var _seg_on := PackedByteArray()
var _seg_d := PackedFloat64Array()   # A 段算的本只到队长的距离（移动前）：C 段接触 / 泪照原来的语义用它
var _dv_e := PackedInt32Array()
var _dv_o := PackedInt32Array()
var _ab_e := PackedInt32Array()
var _ab_o := PackedInt32Array()


func update(dt: float) -> void:
	var dark_mod: float = Bal.v("lamp/dark_enemy", 1.2) if g.lamp < 30.0 else 1.0   # 灯火暗淡时敌人移速 / 接触伤害倍率（docs/88 旋钮，缺省 1.2 不变）
	# 敌人更新分三段（docs/101 B7 ③，10-15 起换基线）：
	#   A 决策（逐只：计时、持续伤害、远距回收、进化、Boss 步、AI 意图 → 本帧速度 v）
	#   B 运动（逐只：分离、积分、场地约束、景物推出；不抽随机数、不回调——将来的原生 EnemyCore.step）
	#   C 结算（逐只：吞噬掷骰、伊祖米克吸收、囊海爬行者爆发、接触伤害 / 形变、泪的持续伤害；距离按移动后的位置）
	# 原来一只敌人走完全部再下一只；分段后先后次序不同，同 seed 结果随之改变。本帧新刷出的敌人（A 里 Boss 召唤等）三段都不处理，与原来一致
	var n: int = g.enemies.size()
	_seg_v.resize(n)
	_seg_on.resize(n)
	_seg_d.resize(n)
	_dv_e.clear()
	_dv_o.clear()
	_ab_e.clear()
	_ab_o.clear()
	# ---- A 决策段
	for i in n:
		_seg_on[i] = 0
		var e: Dictionary = g.enemies[i]
		if e.dead:
			continue
		e.age += dt
		if float(e.get("set_t", 0.0)) > 0.0:
			e.set_t = maxf(0.0, e.set_t - dt)
			if e.set_t == 0.0:
				e.weak = D.ENEMIES[e.type].get("weak", "")
				g.vfx.add_text(e.pos + Vector2(0, -24), "架起结束", Color(0.75, 0.8, 0.9), 13)
		e.flash -= dt
		e.jhit -= dt
		e.stun -= dt / g.control_mult
		# 韧性钩子（docs/38 §1.5）：白名单 Boss 身上的眩晕一定来自玩家一方（Boss 自己的硬直写 break_t），换成韧性后清零，不会被锁死
		if e.boss and e.stun > 0.0 and g.combat.tough_on(e):
			g.combat.add_tough(e, e.stun * Bal.v("boss/tough_per_stun", 5.0))
			e.stun = 0.0
		e.squash -= dt
		e.slow -= dt / g.control_mult
		# 灯边硬直（docs/56 §10，beacon.melee_stagger 写入）：和眩晕一样不移动、不出招，但不是 e.stun（不吃控制时长加成、不触发「对眩晕敌人」的加成）
		var bst: float = e.get("bstag", 0.0)
		if bst > 0.0:
			bst -= dt
			e.bstag = bst
		if e.get("wind", 0.0) > 0.0:
			e.wind -= dt
		if e.get("pose", 0.0) > 0.0:
			e.pose -= dt
		# 不可索敌的第一形态仍参与公共动画计时；移动/治疗交给遭遇模块，不走敌对 AI 和接触伤害。
		if e.get("friendly", false):
			g.ishar.step_ally(e, dt)
			continue
		if e.get("haste", 0.0) > 0.0:
			e.haste -= dt
		if e.get("aura_weak", 0.0) > 0.0:
			e.aura_weak -= dt
		if e.get("lit", 0.0) > 0.0:
			e.lit -= dt
		if e.get("requiem", 0.0) > 0.0:
			e.requiem -= dt
		# 流血（狙击干员）：每 0.5 秒结算一次
		if e.get("bleed", 0.0) > 0.0:
			e.bleed -= dt
			e["bleed_t"] = e.get("bleed_t", 0.0) + dt
			if e.bleed_t >= 0.5:
				e.bleed_t = 0.0
				g.combat.damage(e, e.bleed_dps * 0.5, g.combat.make_hit("援护"))
				g.fx.append({"kind": "spark", "pos": e.pos + Vector2(randf_range(-6, 6), -4), "vel": Vector2(0, 60), "sz": 2.0, "life": 0.4, "max": 0.4, "col": Color(0.8, 0.05, 0.1)})
				if e.dead:
					continue
		# 侵蚀（排异·无解困境）：受控敌人每 0.5 秒受一次触手法术伤害
		if e.get("corr_t", 0.0) > 0.0:
			e.corr_t -= dt
			e["corr_tick"] = e.get("corr_tick", 0.0) + dt
			if e.corr_tick >= 0.5:
				e.corr_tick = 0.0
				g.combat.damage(e, e.corr_dmg, g.combat.make_hit("触手", ["corrode"]))
				g.fx.append({"kind": "spark", "pos": e.pos + Vector2(randf_range(-8, 8), -6), "vel": Vector2(0, -40), "sz": 2.5, "life": 0.45, "max": 0.45, "col": Color(1.2, 0.6, 1.6)})
				if e.dead:
					continue
		var to: Vector2 = g.ppos - e.pos
		var dist := to.length()
		var dir: Vector2 = to / max(dist, 0.001)
		if abs(dir.x) > 0.1 and e.ai != "static":
			e.fx = sign(dir.x)

		if e.chest:
			if dist > 1500.0:
				if e.get("event", "") != "":
					# 海嗣祭坛不静默删除（事件验收 P2-8）：挪到主控前方约 600 处，保留剩余窗口；屏外方位指示在 hud.gd
					g.endg.reposition_box(e)
				else:
					e.dead = true
			continue
		if dist > 1300.0 and not e.boss:
			if e.ai == "static" or e.get("dormant", false):
				e.dead = true
			else:
				e.pos = g.spawner.edge_pos()
			continue

		if not e.evo and not e.elite and not e.boss and e.ai != "static" and e.age > EVO_AGE * maxf(0.55, 1.0 - g.t / 900.0):
			evolve(e)

		# 注亡拟嗣：生命持续流失
		if e.type == "brood":
			e.hp -= e.maxhp * 0.08 * dt
			if e.hp <= 0.0:
				e.dead = true
				continue
		if e.boss:
			g.bai.boss_step(e, dt, dir, dist)
		if e.dead:
			continue

		# ---- 移动
		# 重型怪只削外来击退；自己冲锋 / 突刺（kb_self，boss_ai 的 dash / stab）不削，否则骑士冲锋只冲出 1/3（用户实机反馈 9/27）
		var v: Vector2 = e.kb * (0.3 if D.ENEMIES[e.type].get("heavy", false) and not e.get("kb_self", false) else 1.0)
		var spd: float = e.spd * dark_mod * (0.65 if e.slow > 0.0 else 1.0) * g.beacon_sys.slow_mult(e)
		if e.get("lead_charge", false) and dist < Bal.v("enemy/horde_lead_charge_r", 320.0) and e.get("wake_t", 0.0) <= 0.0 and e.stun <= 0.0 and not g.eai.busy(e):
			# 领头冲撞（docs/116 §7.4）：大群领头的重型怪 / 精英第一次逼近时起一次带地面预警的直线冲撞（复用 telegraph 的 dash）
			e.lead_charge = false
			g.tele.warn(e, "line", Bal.v("enemy/horde_lead_charge_warn", 0.8), {"ang": dir.angle(), "len": clampf(dist + 60.0, 160.0, 420.0), "wid": 26.0, "track": 0.3,
				"act": "dash", "fit_len": true, "name": "", "col": Color(1.0, 0.4, 0.55), "dmg": 0.0})
		if e.get("rush", 0.0) > 0.0:
			# 合围冲锋段（docs/116 §7.3）：大群入场时 × rush，进到队长 horde_rush_r 内回到正常速度（只降不升）
			if dist <= Bal.v("enemy/horde_rush_r", 180.0):
				e.rush = 0.0
			else:
				spd *= float(e.rush)
		if not e.boss:
			# 藏品（docs/57 P1 / P2）：非 Boss 敌人的移速与受到的击退倍率；自己冲锋（kb_self）不算击退
			spd *= g.enemy_speed_mult
			if not e.get("kb_self", false):
				v *= g.enemy_kb_mult
		if e.get("channel", 0.0) > 0.0 or e.get("coma", false) or e.get("wind", 0.0) > 0.0 or e.get("dormant", false) or e.get("wake_t", 0.0) > 0.0:
			spd = 0.0
		if e.get("haste", 0.0) > 0.0:
			spd *= 1.4
		var move_dir := dir
		if e.feed and final_target_valid(e):
			move_dir = (by_id(e.feed_to_id).pos - e.pos).normalized()
		elif e.get("aggro", Vector2.INF) != Vector2.INF:
			# 海嗣分身吸引仇恨：本帧朝分身走（每帧由分身重新标记）
			move_dir = (e.aggro - e.pos).normalized()
			e.aggro = Vector2.INF
		var held: bool = e.stun > 0.0 or bst > 0.0
		# 封印（docs/61 §15 st.seal，干员积木）：非 Boss 敌人不起新的特殊招式（pattern：冲刺 / 吐酸 / 环弹 / 神经光环 / 额外招式……），
		# 已经起手的蓄力 / 冲刺 / 自爆照常走完（enemy_ai.busy）；Boss 的封印在 boss_ai 的 ready 里。没有封印时 seal_t 不存在，这里恒为 false
		var sealed: bool = float(e.get("seal_t", 0.0)) > g.t
		var ov: Vector2 = g.eai.pattern(e, dir, dist, dt, spd) if not held and not (sealed and not e.boss and not g.eai.busy(e)) else Vector2.INF
		if ov != Vector2.INF:
			v += ov
		elif not held:
			match e.ai:
				"melee":
					v += move_dir * spd
				"ranged":
					if e.get("hover", false) == false and D.ENEMIES[e.type].get("entrench", false) and not e.set_done and dist < e.range:
						# 固海凿石者：首次接敌时原地架起，大幅提高防御
						e.set_done = true
						e.set_t = 20.0
						e.weak = "法术"
						g.vfx.add_text(e.pos + Vector2(0, -24), "架起 · 法术弱点", Color(0.75, 0.8, 0.9), 14)
					if e.set_t > 0.0:
						pass
					elif dist > e.range * 0.85:
						v += dir * spd
					if e.set_t <= 0.0 and e.set_done:
						e.weak = D.ENEMIES[e.type].get("weak", "")
					e.cdt -= dt
					if spd > 0.0 and dist < e.range and e.cdt <= 0.0 and (not e.boss or e.age >= 2.0) and not g.beacon_sys.ranged_held(e) and not sealed:   # sealed：封印期间不远程开火（冷却留着）   # 圈内安全：读条期间远程杂兵不开火，冷却留着出圈即打（docs/49g）
						if not e.boss and not e.get("shot_ready", false):
							e["shot_ready"] = true
							e["shot_wind_until"] = g.t + 0.35
						elif g.t >= float(e.get("shot_wind_until", 0.0)):
							e["shot_ready"] = false
							e.cdt = e.cd * (0.82 if e.boss else g.enemy_ranged_cd_mult)   # 捕鳞蓑（docs/57 P5）：远程杂兵开火间隔
							g.eai.shoot(e, dir)
		e.kb = e.kb.move_toward(Vector2.ZERO, 900.0 * dt)
		if e.get("kb_self", false) and e.kb == Vector2.ZERO:
			e.kb_self = false
		_seg_v[i] = v
		_seg_on[i] = 1
		_seg_d[i] = dist

	# ---- B 运动段（docs/101 B8：段首把热字段读进平行数组，核心只读写数组，段尾写回字典；核心将来换原生 EnemyCore.step，OPT_CPP 对照）
	_hot_gather(n)
	if not _motion_native(n, dt):
		_motion_core(n, dt)
	_hot_scatter(n)

	# ---- C 结算段
	var dv := 0
	var ab := 0
	var ndv: int = _dv_e.size()
	var nab: int = _ab_e.size()
	for i in n:
		if _seg_on[i] == 0:
			continue
		var e: Dictionary = g.enemies[i]
		# 吞噬：B 段登记的候选按分离次序掷骰（rng_enemy，1.5%）
		while dv < ndv and _dv_e[dv] == i:
			var prey: Dictionary = g.enemies[_dv_o[dv]]
			dv += 1
			if not e.dead and not prey.dead and g.rng_enemy.randf() < 0.015:
				_devour(e, prey)
		# 伊祖米克吸收子代：强化层数（不再回血，docs/38 §8.7）
		if ab < nab and _ab_e[ab] == i:
			var iz: Dictionary = g.enemies[_ab_o[ab]]
			ab += 1
			if not e.dead:
				e.dead = true
				g.bai.izumik_absorb(iz)
			continue
		if e.dead:
			continue
		var dist: float = _seg_d[i]   # 接触 / 泪按本只移动前的距离判（与原来「一只走完再下一只」相同；B7 ③ 一度改成移动后，Ⅷ 熟练胜率 −20 点，10-15 改回）
		# ---- 囊海爬行者：每失去 15% 生命爆发一次。有 0.8 秒鼓胀预警（docs/48 P0-6：原 0.4 秒低于 0.6 下限），爆发之间至少隔 1.2 秒（高输出下不会连爆秒人）
		if e.has("burst_at"):
			e.burst_cd = maxf(0.0, e.get("burst_cd", 0.0) - dt)
			if e.get("burst_w", 0.0) > 0.0:
				e.burst_w -= dt
				if e.burst_w <= 0.0:
					g.fx.append({"kind": "ring", "pos": e.pos, "r": 80.0, "life": 0.4, "max": 0.4, "col": Color(0.8, 0.45, 1.0)})
					# 破膜帧条（docs/96 §1.3，纯画面）：world._draw_enemy_full 按 burst_fx_t 在本体前后各画一层；地面残留 fx_pocket_puddle 在溟痕层
					e["burst_fx_t"] = g.t
					var pf: String = str(D.ENEMIES[e.type].get("puddle_fx", ""))
					if pf != "":
						g.vfx.fx_sprite(pf, e.pos + Vector2(0, e.r * 0.8 + 3.0 * Game.PX + 4.0 * Game.PX), D.enemy_scale(e, g.t, Game.PX), 0.0, false, false, Color.WHITE, true)
					Sfx.play("tentacle", -2.0, 0.7)
					if g.combat.ground_d(g.ppos, e.pos) < 80.0:   # 画即判（§1.9）
						g.combat.enemy_hit(e.dmg * 0.5, {"corrode": 0.0, "nerve": 12.0}, true, false, ["近战", "法术"])
			elif e.hp <= e.burst_at and e.burst_cd <= 0.0:
				e.burst_at -= e.maxhp * 0.15
				e.burst_w = 0.8
				e.burst_dur = 0.8   # 画面按 burst_w / burst_dur 算鼓胀进度（界面与美术）
				e.burst_cd = 1.2
		# ---- 接触伤害
		# 休眠中的收割者、自爆的狂奔者（V8）没有接触伤害；Boss 登场 2 秒内不造成接触伤害（docs/38 B0 第 6 项：边缘刷出贴脸）
		if e.dmg > 0.0 and (e.ai == "melee" or e.type == "brood") and dist < e.r + 12.0 and not e.get("coma", false) and not e.get("dormant", false) and not (e.type == "reaper" and e.get("wake_t", 0.0) > 0.0) and not D.ENEMIES[e.type].get("no_contact", false) and not (e.boss and e.age < 2.0) and e.get("air", 0.0) <= 0.0 and not e.get("under", false) and float(e.get("hatch_until", 0.0)) <= g.t:
			if D.ENEMIES[e.type].get("morph", false):
				morph(e)
				continue
			if g.invuln <= 0.0:
				# 底海滑动者冲刺撞击：熄灭灯火
				if e.type == "slider" and e.get("dash_t", 0.0) > 0.0:
					g.lamp = maxf(0.0, g.lamp - 8.0 * g.lamp_loss_mult)
					g.vfx.add_text(g.ppos + Vector2(20, -60), "灯火 -8", Color(1.0, 0.6, 0.4), 14)
				g.combat.enemy_hit(e.dmg * dark_mod, e, false, false, ["近战", "物理"], "contact_" + e.type)
				e.atk_until = g.t + 0.2   # 近战出手：atk_anim 的敌人播攻击帧条第 3、4 帧
		# 伊莎玛拉之泪：站在上面持续受到真实伤害（Boss 的机制物件，算 Boss 来源）
		if e.type == "tear" and dist < e.r + 14.0:
			g.combat.lose_hp(6.0 * dt, "tear", true)
			g.hurt_flash = max(g.hurt_flash, 0.05)

	build_grid()   # 移动后重建网格：之后的干员索敌 / 子弹 / 敌弹查询用本帧新位置（docs/101 §3.4 ⑧）


## 吞噬：进化体吞掉身边的普通怪（分离循环里按 1.5% 概率触发）
func _devour(e: Dictionary, o: Dictionary) -> void:
	e.hp += o.hp
	e.maxhp += o.maxhp
	var esc: float = float(e.get("sc", 1.0))   # 怪物体型（spawner.escale）：增量与上限同比放大
	e.r = min(e.r + 1.5 * esc, 32.0 * esc)
	e.xp += o.xp
	o.dead = true
	g.vfx.add_text(e.pos, "吞噬", Color(1.0, 0.4, 0.5))


## 喂食目标（feed_to_id，伊祖米克）还在且未死；已被清理的 by_id 返回 null，按已死算（docs/101 B5）
func final_target_valid(e: Dictionary) -> bool:
	if not e.has("feed_to_id"):
		return false
	var t = by_id(int(e.feed_to_id))
	return t != null and not t.dead


## 伊祖米克的子代：碰到水月就蜕变成其他敌人
func morph(e: Dictionary) -> void:
	e.dead = true
	g.fx.append({"kind": "ring", "pos": e.pos, "r": 40.0, "life": 0.3, "max": 0.3, "col": Color(0.6, 1.0, 0.6)})
	g.vfx.add_text(e.pos + Vector2(0, -24), "蜕变", Color(0.6, 1.0, 0.6), 16)
	for k in 2:
		g.spawner.spawn_enemy(["bone", "slider", "stone"][g.rng_enemy.randi() % 3], e.pos + Vector2.from_angle(g.rng_enemy.randf() * TAU) * 20.0)


## 敌方投射物推进已搬到 enemies/shot_pool.gd（g.shots.step，docs/101 B7 ④）；这里留旧含义的转发（测试与旧调用）：
## update_ebullets = 抛物 + 敌弹（不含冲击环，冲击环见 g.shots.update_shocks）
func update_ebullets(dt: float) -> void:
	g.shots.update_lobs(dt)
	g.shots.update_ebullets(dt)


func update_lobs(dt: float) -> void:
	g.shots.update_lobs(dt)


## 玩家身上的持续状态：侵蚀掉血、神经损伤衰减、溟痕
func update_status(dt: float) -> void:
	g.combat.update_ctrl(dt)   # 主控减速计时；Boss 战中僵直恒为 0（docs/38 §1.11）
	g.combat.update_ailments(dt)   # 小怪控制：寒霜 / 冻结 / 束缚 / 侵蚀创口
	g.pstun -= dt
	g.atk_slow -= dt
	g.frost = maxf(0.0, g.frost - dt)
	if g.corrode_pool > 0.0:
		var tick: float = min(g.corrode_pool, (g.corrode_pool * 0.5 + 1.0) * dt)
		g.combat.drain_corrode(tick)
	var mired := false
	var mire_nat := false   # 站在自然溟痕里（不是 Boss 子弹留下的）：这一跳不算 Boss 来源
	var sanct: bool = g.squad.in_sanctuary(g.ppos)   # 流明灯塔：区内溟痕失效
	for m in g.mires:
		m.life -= dt
		m.r = min(m.maxr, m.r + 5.0 * dt)
		if g.combat.ground_d(g.ppos, m.pos) < m.r and not sanct:
			mired = true
			if not m.get("boss", false):
				mire_nat = true
	# 溟痕：减速 + 屏幕变暗 + 持续掉血；神经损伤在溟痕里累积（combat，Boss与怪物 419c84d）
	g.in_mire = move_toward(g.in_mire, 1.0 if mired else 0.0, dt * (4.0 if mired else 2.5))
	update_nest_aura(dt, sanct)
	g.combat.update_nerve(dt, mired, sanct)   # 神经损伤：站在溟痕里累积（combat.gd）
	if mired:
		# 溟痕侵蚀：每 0.5 秒结算一次（3 + 1.5% 最大生命），带飘字与轻微红闪
		mire_tick -= dt
		if mire_tick <= 0.0:
			mire_tick = 0.5
			# 自然溟痕每跳（0.5 秒）：enemy/mire_flat + 最大生命 × enemy/mire_pct，再乘难度修正 mire_dmg（缺省 3 + 1.5%）；
			# 只踩在 Boss 溟痕里时每跳 boss/mire_pct 1%（每秒 2%，不再有固定 +3，docs/38 §1.7）
			var md: float = ((Bal.v("enemy/mire_flat", 3.0) + g.max_hp * Bal.v("enemy/mire_pct", 0.015)) * float(g.dmod.get("mire_dmg", 1.0))) if mire_nat else g.max_hp * Bal.v("boss/mire_pct", 0.01)
			md = g.combat.lose_hp(md, "mire", not mire_nat)
			if md >= 1.0:   # Boss 溟痕这一跳被持续伤害上限截到不足 1 点时不闪、不飘「-0」（自然溟痕每跳 ≥3，照旧）
				g.red_flash = maxf(g.red_flash, 0.08)
				g.hp_shake = 0.2
				g.hurt_flash = maxf(g.hurt_flash, 0.06)
				g.vfx.add_text(g.ppos + Vector2(randf_range(-10, 10), -80), "-%d 溟痕" % int(md), Color(0.85, 0.45, 1.0), 15)
		g.head_bar_t = maxf(g.head_bar_t, 0.6)
	else:
		mire_tick = 0.0
	g.mires = g.mires.filter(func(m): return m.life > 0.0)


func evolve(e: Dictionary) -> void:
	e.evo = true
	e.maxhp *= 1.8
	e.hp = e.maxhp
	e.r *= 1.3
	e.spd *= 1.15
	e.dmg *= 1.5
	e.xp *= EVO_XP
	g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.0, "life": 0.3, "max": 0.3, "col": Color(1.0, 0.3, 0.4)})


func nearest(n: int, max_dist: float, origin: Vector2 = Vector2.INF) -> Array:
	if origin == Vector2.INF:
		origin = g.ppos
	var c: Array = []
	for j in query(origin, max_dist):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var d: float = e.pos.distance_squared_to(origin)
		if d < max_dist * max_dist:
			# 部件（e.part：塑路者核心、偏执泡影茧壳等，docs/38 §8）在射程内时排在普通敌人前面；只影响标了部件的单位，不是全局 Boss 加权
			c.append([d - (1.0e12 if e.get("part", false) else 0.0), e])
	c.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for i in min(n, c.size()):
		out.append(c[i][1])
	return out


## origin 周围 max_dist 内的活敌人（入选条件同 nearest，不排序；按网格查询顺序，同 seed 稳定）
func in_range(max_dist: float, origin: Vector2 = Vector2.INF) -> Array:
	if origin == Vector2.INF:
		origin = g.ppos
	var out: Array = []
	for j in query(origin, max_dist):
		var e: Dictionary = g.enemies[j]
		if not e.dead and e.pos.distance_squared_to(origin) < max_dist * max_dist:
			out.append(e)
	return out


## 扇形判定：返回 origin 周围 radius 内、与 ang 夹角不超过 half 的敌人
func arc_hit(origin: Vector2, ang: float, half: float, radius: float) -> Array:
	var out: Array = []
	for j in query(origin, radius + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var off: Vector2 = e.pos - origin
		if off.length() > radius + e.r:
			continue
		if half < PI and abs(angle_difference(ang, off.angle())) > half + 0.15:
			continue
		out.append(e)
	return out


## 敌人最密集的位置（在 radius 内采样）
func densest_point(radius: float, origin: Vector2 = Vector2.INF) -> Vector2:
	var best := Vector2.INF
	var bn := 0
	var cand := nearest(12, radius, origin)
	for c in cand:
		var n := 0
		for j in query(c.pos, 90.0):
			if not g.enemies[j].dead and g.enemies[j].pos.distance_to(c.pos) < 90.0:
				n += 1
		if n > bn:
			bn = n
			best = c.pos
	return best


## ---- 击退统一入口（docs/101 B7 ②⑥）：所有对敌人的击退冲量都经 apply_kb。失重（安洁莉娜 st.weightless，e.wl_t / e.wl_kb）倍率在这里乘
## （原来 19 处直接写 e.kb、只有 4 处乘了）；精英 ×0.3 这类按招式定的系数仍由调用方乘进 v；重型 / 藏品击退倍率在 A 段算速度时统一乘。
## wl = false：调用方已经按失重算过（安洁莉娜按位移距离反算冲量，失重折进距离），不再乘
static func kb_taken(e: Dictionary, t: float) -> float:
	return float(e.wl_kb) if e.has("wl_t") and float(e.wl_t) > t else 1.0


func apply_kb(e: Dictionary, v: Vector2, wl := true) -> void:
	e.kb += v * kb_taken(e, g.t) if wl else v


# ---- 干员 / 藏品改敌人控制状态的统一入口（docs/101 §7.3.10，10-15）：写法统一，语义照旧（同 seed 逐位不变）。
# 字典仍是权威数据；原生 B 段只写 pos，这些字段由 A 段（GDScript）读。

## 眩晕 / 减速取大合并；-INF = 这一项不动。精英 / Boss 系数各干员不同，由调用方乘好再传
func add_cc(e: Dictionary, stun := -INF, slow := -INF, kind := "") -> void:
	var d: Dictionary = D.ENEMIES.get(e.type, {})
	var mult: float = float(d.get("cc_duration_mult", 1.0))
	if kind == "stop" and d.get("stop_immune", false):
		return
	if kind == "cold" and d.get("cold_immune", false):
		return
	if stun > -INF and (kind == "airborne" or not d.get("stun_immune", false)):
		e.stun = maxf(e.stun, stun * (1.0 if kind == "airborne" else mult))
	if slow > -INF:
		e.slow = maxf(e.slow, slow * (mult if kind == "cold" else 1.0))


## 浮空高度（画面抬高、C 段接触判定读）；hold_kb = 本帧同时清掉击退（被掀飞 / 抛起期间不吃击退）。
## 安洁莉娜的托举原本不清击退，所以清不清由调用方定，不在这里强行统一（统一会变基线）
func set_air(e: Dictionary, h: float, hold_kb := false) -> void:
	e.air = h
	if hold_kb:
		e.kb = Vector2.ZERO


## 强制位移：本帧把敌人放到 p 并清击退（锚 / 钩拖拽）
func hold_at(e: Dictionary, p: Vector2) -> void:
	e.pos = p
	e.kb = Vector2.ZERO


## 位移增量（常驻拖慢、晶柱推开）
func nudge(e: Dictionary, delta: Vector2) -> void:
	e.pos += delta


## 嘲讽：下一帧朝 p 走（A 段读后清回 INF）
func set_aggro(e: Dictionary, p: Vector2) -> void:
	e.aggro = p


# ---- 出生口 / 槽位 / id 表（docs/101 B5，§4.3）：所有敌人经 admit 进 g.enemies（spawner.spawn_enemy / spawn_chest 两处），
# 分配槽位 e.slot（原生端热字段平行数组的下标；空闲槽位后进先出复用）并登记 id 表；sweep_dead（game._cleanup / enemy_demo 每步）
# 去掉已死的、回收槽位。测试里直接改 g.enemies 的敌人不经这里，不影响槽位表
var _slot_free := PackedInt32Array()
var _slot_n := 0               # 用过的最大槽位数（平行数组的长度）
var _by_id := {}               # e.id -> 敌人字典（admit 时登记，sweep_dead 回收时删）


func admit(e: Dictionary) -> void:
	var nf: int = _slot_free.size()
	if nf > 0:
		e["slot"] = _slot_free[nf - 1]
		_slot_free.resize(nf - 1)
	else:
		e["slot"] = _slot_n
		_slot_n += 1
	_by_id[e.id] = e
	g.enemies.append(e)


## id → 敌人字典；已被 sweep_dead 回收（或从没经 admit）的返回 null
func by_id(id: int):
	return _by_id.get(id)


func slot_count() -> int:
	return _slot_n


## 去掉已死的敌人并回收槽位，返回新数组（顺序不变，与原来的 arr.filter(not dead) 等价；每次都返回新数组，种类登记照旧据此重建）
func sweep_dead(arr: Array) -> Array:
	var keep: Array = []
	for e in arr:
		if not e.dead:
			keep.append(e)
		elif e.has("slot") and is_same(_by_id.get(e.id), e):
			_slot_free.append(int(e.slot))
			_by_id.erase(e.id)
	return keep


# ---- 部件与种类登记（docs/101 S7）：消掉每次击杀 / 刷怪对 g.enemies 的全表扫描。只是索引，读的时候照样看敌人身上的实时字段（dead / part），
# 所以不管谁在哪里把 dead 设成 true 都不会算错；结果和全表扫描逐个相同（同种子 TRACE 不变）
var _parts: Array = []        # 设过 part 的敌人（偏执泡影茧、塑路者核心分形；只有这两处设 part）
var _ti_arr = null            # 种类登记对应的 g.enemies 数组对象（_cleanup 每帧换新数组 → 重建）
var _ti_n := 0                # 已登记到 g.enemies 的第几个
var _ti_last = null           # 最后登记的那一只（数组被 clear 后又塞满时用它认出来）
var _by_type: Dictionary = {} # type -> 这一类的敌人（含已死，计数时跳过）


## 设 part = true 的地方调用（paranoia.gd 结茧、path.gd 猎核）
func part_add(e: Dictionary) -> void:
	for o in _parts:
		if is_same(o, e):
			return
	_parts.append(e)


## 现存部件（未死且 part 仍为 true），顺序与 g.enemies 一致（两只以上时按 g.enemies 重排，击杀吸取的结算顺序和原来的全表扫描相同）
func parts() -> Array:
	_parts = _parts.filter(func(o): return not o.dead and o.get("part", false))
	if _parts.size() > 1:
		var ordered: Array = []
		for e in g.enemies:
			for o in _parts:
				if is_same(o, e):
					ordered.append(e)
		_parts = ordered
	return _parts


## 场上某一类的存活数（spawner.type_n 用）：按 g.enemies 增量登记，只数这一类；g.enemies 换了数组 / 被清空重填时重建
func type_alive(kind: String) -> int:
	var arr: Array = g.enemies
	if not is_same(_ti_arr, arr) or arr.size() < _ti_n or (_ti_n > 0 and not is_same(arr[_ti_n - 1], _ti_last)):
		_ti_arr = arr
		_ti_n = 0
		_by_type = {}
	for i in range(_ti_n, arr.size()):
		var e: Dictionary = arr[i]
		if not _by_type.has(e.type):
			_by_type[e.type] = []
		_by_type[e.type].append(e)
	_ti_n = arr.size()
	_ti_last = arr[_ti_n - 1] if _ti_n > 0 else null
	var n := 0
	for e in _by_type.get(kind, []):
		if not e.dead:
			n += 1
	return n


## 重叠巢涌光环只取最强一只；离圈不积攒下一次伤害。
func update_nest_aura(dt: float, sanct: bool) -> void:
	var source: Dictionary = {}
	var dps := 0.0
	if not sanct:
		for e in g.enemies:
			var d: Dictionary = D.ENEMIES.get(e.type, {})
			if not d.has("aura_arts_mult") or e.dead or e.stun > 0.0 or float(e.get("seal_t", 0.0)) > g.t:
				continue
			if g.ppos.distance_to(e.pos) >= float(d.aura_r):
				continue
			var rate: float = e.dmg * float(d.aura_arts_mult)
			if rate > dps:
				dps = rate
				source = e
	if source.is_empty():
		nest_tick = 0.0
		return
	var period: float = D.ENEMIES[source.type].aura_tick
	nest_tick += dt
	if nest_tick < period:
		return
	nest_tick = fmod(nest_tick, period)
	if g.invuln > 0.0:
		return
	source["aura_pulse_t"] = g.t
	g.combat.enemy_hit(dps * period, {"type": source.type, "elite": source.elite, "boss": false}, false, true, ["远程", "法术"], "nest")
