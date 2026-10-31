## 干员 → 主场景的接口层（2026-09-26 架构整理）：干员脚本需要 game.gd 提供的能力（索敌、伤害、特效、飘字、绘制……）
## 一律通过这里的方法调用，不直接调用 game.gd 里下划线开头的内部函数。
## 好处：game.gd 以后拆分 / 改名 / 改参数时只改这一个文件，13 名干员不受影响；这里也就是「干员能用什么」的完整清单。
## 读写 game.gd 的公共状态（ppos、enemies、stats、hitstop、t 等）和 CanvasItem 绘制（g.draw_*）不在此列，仍直接用 g。
## 继承关系：op_api.gd ← character.gd ← <干员>.gd
extends RefCounted

const _BalG = preload("res://scripts/core/balance.gd")   # data/balance.json 旋钮（add_cc_growth 读 growth 段）；名字带下划线避免和子类 const Bal 重名

var g                      # Game (Node2D)

## 绘制入口（性能 9/30）：干员脚本画东西一律 cv.draw_*（同 CanvasItem 接口）。编队的合批画布（squad.cv，batch_canvas.gd）：
## 平时直接转给 g；在编队「地面实体」「技能上层」两个阶段里把几何图形合成一批提交。没有编队（图鉴等）时就是 g
var _cv = null
var cv:
	get:
		if _cv == null:
			var s = g.get("squad") if g != null else null
			_cv = s.cv if s != null and "cv" in s else g
		return _cv


# ---------------------------------------------------------------- 「以队长为中心」的范围中心（docs/209 §1.3）
## 积木里 center / at = leader 的范围：平时是队长位置；指挥 v2（command/self_center）下这名队友突击 / 部署中时改以她自己为中心
func lead_pos() -> Vector2:
	var sq = g.get("squad") if g != null else null
	if sq != null and sq.has_method("self_center") and sq.self_center(self):
		return get("pos")
	return g.ppos


# ---------------------------------------------------------------- 索敌

## 离 origin（缺省为主控位置）最近的 n 个活着的敌人，max_dist 以内，按指挥优先级排序（prio_order；队长恒为 Boss 优先）。
## Boss 优先（缺省；2026-09-29 协调人：普通档打不动 3:30 的第一个 Boss，输出被身边小怪抢走）：balance ai/boss_focus（缺省 1 = 开）时，
## max_dist 内有可受击的 Boss 就排到第一个；部件（e.part）优先照旧；主控 ai/boss_focus_guard（60）内有小怪贴脸时不强制（护主）
## 只剩无敌目标时照常返回它（普攻照打、不扣血；10-28 用户：「面对无敌的敌人可以继续普通攻击，但是可以不放技能」，
## 技能另由 has_hittable / data_operator.skill_gate_ok 暂缓）
func nearest_enemies(n: int, max_dist: float, origin: Vector2 = Vector2.INF) -> Array:
	var o: Vector2 = g.ppos if origin == Vector2.INF else origin
	var cands: Array = []
	# 主轴目标（docs/142b §1.0，10-25）：射程内有部件（泡影茧、伊莎玛拉连线海嗣、伊祖米克子代 / 茧、塑路者截停的分形……）就先打最近的部件，
	# 再轮到指挥优先级——自动攻击下玩家选不了目标，只管把它们带进射程
	var part = null
	var pd: float = max_dist * max_dist
	for p in g.enemies_sys.parts_live():
		var d2: float = p.pos.distance_squared_to(o)
		if d2 < pd and hittable(p):
			pd = d2
			part = p
	if part != null:
		var outp: Array = hit_first(g.enemies_sys.nearest(n, max_dist, origin))
		outp.erase(part)
		outp.push_front(part)
		if outp.size() > n:
			outp.resize(n)
		return outp
	var mb = mid_boss_lock(o, max_dist)
	if mb != null:
		var outm: Array = hit_first(g.enemies_sys.nearest(n, max_dist, origin))
		outm.erase(mb)
		outm.push_front(mb)
		if outm.size() > n:
			outm.resize(n)
		return outm
	if prio_mode() == 1:
		for e in g.enemies_sys.nearest(mini(maxi(n * 6, 14), 24), max_dist, origin):
			cands.append([e, e.pos.distance_to(o)])
		var out1: Array = hit_first(prio_order(cands, 1))
		if out1.size() > n:
			out1.resize(n)
		return out1
	var near: Array = g.enemies_sys.nearest(n, max_dist, origin)
	for e in near:
		if not hittable(e):   # 最近的几个里有打不动的（无敌 Boss 等）：放宽候选，能受击的排前、打不动的垫底
			near = hit_first(g.enemies_sys.nearest(mini(maxi(n * 6, 14), 24), max_dist, origin))
			break
	if near.is_empty() or near[0].boss or near[0].get("part", false) or not hittable(near[0]):
		if near.size() > n:
			near.resize(n)
		return near
	for e in near:
		cands.append([e, e.pos.distance_to(o)])
	var bd: float = max_dist * max_dist
	for e in _focus_bosses():   # 不在最近 n 个里、但在 max_dist 内的 Boss 也进候选（排在后面，得分 = 距离）
		if not e.dead and e.pos.distance_squared_to(o) < bd and not near.has(e):
			cands.append([e, e.pos.distance_to(o)])
	var out: Array = prio_order(cands, 0)
	if out.size() > n:
		out.resize(n)
	return out


## 中期 Boss 战锁定（docs/177 §9 方案 A，10-30 协调人定；boss/mid_focus 0 = 关）：中期 Boss（非结局最终 Boss）可受击、离 origin 在
## 射程 × boss/mid_focus_k（1.5）内，就排到第一个——清杂 / Boss 优先两档都一样，技能（非范围）同样先选它；
## 护主只留给队长自己，且只认 boss/mid_focus_guard（30）像素内贴脸的杂兵。返回 Boss 或 null
func mid_boss_lock(o: Vector2, max_dist: float):
	var BalS = preload("res://scripts/core/balance.gd")
	if BalS.v("boss/mid_focus", 1.0) <= 0.0 or g.get("spawner") == null:
		return null
	var r: float = max_dist * BalS.v("boss/mid_focus_k", 1.5)
	var best = null
	var bd: float = r * r
	for e in _focus_bosses():
		if not e.get("boss", false) or g.spawner.is_final_boss_type(str(e.type)):
			continue
		var d2: float = e.pos.distance_squared_to(o)
		if d2 < bd:
			bd = d2
			best = e
	if best != null and bool(get("is_leader")):
		var gd: Array = g.enemies_sys.nearest(1, BalS.v("boss/mid_focus_guard", 30.0), g.ppos)
		if not gd.is_empty() and not gd[0].boss:
			return null
	return best


## 自动选敌认的「打得动」（10-28 用户：「自动攻击的索敌会打无敌的敌人，特别是打伊祖米克的时候刚开始都在打它，没有打水母」）：
## 与 combat.damage 挡伤害的条件一致——无敌（伊祖米克学习期等）、过卡点无敌 / 阶段护盾、Boss 自己挡（伊莎玛拉变身）、
## 囊海爬行者鼓胀、假死、潜地都算打不动。自动选敌（nearest_enemies / 突击走位 / 能天使 / 德克萨斯 / 随机目标）把它们排到最后，
## 范围里只有它们时照旧打；队长手动瞄准（aim_targets 的瞄准锥）不受影响
func hittable(e: Dictionary) -> bool:
	if e.boss and e.get("invuln", false) and not e.dead and e.get("cocoon_t", 0.0) > 0.0 and e.get("shell_hp", 0.0) > 0.0:
		return true   # 偏执泡影结茧：本体无敌但外壳吃伤害（paranoia.absorb_damage），要打破——算打得动，技能照放
	if e.dead or e.get("invuln", false) or e.get("coma", false) or e.get("under", false) or e.get("burst_w", 0.0) > 0.0:
		return false
	if e.boss:
		if e.get("gate_inv", 0.0) > 0.0 or e.get("gate_hold", false):
			return false
		var bai = g.get("bai")
		var bh = bai.boss(str(e.type)) if bai != null else null
		if bh != null and bh.block_damage(e):
			return false
	return true


## max_dist 内有没有打得动的敌人（技能暂缓用，10-28）：先看 nearest_enemies 的第一个（打得动的排在前），不是再放宽到最近 24 个
func has_hittable(max_dist: float, origin: Vector2 = Vector2.INF) -> bool:
	var ne: Array = nearest_enemies(1, max_dist, origin)
	if ne.is_empty():
		return false
	if hittable(ne[0]):
		return true
	return g.enemies_sys.nearest(24, max_dist, origin).any(func(e): return hittable(e))


## 稳定重排：能受击的在前、打不动的垫底；能受击的里「喂食」中的子代（伊祖米克学习期游向本体的水母，docs/142b 主轴目标）提到最前
func hit_first(arr: Array) -> Array:
	var axis: Array = []
	var ok: Array = []
	var no: Array = []
	for e in arr:
		if not hittable(e):
			no.append(e)
		elif e.get("feed", false):
			axis.append(e)
		else:
			ok.append(e)
	return axis + ok + no


## 指挥优先级（docs/114 §13，指挥圆盘下半圈）：0 = Boss 优先（缺省，也是改动前的逻辑）/ 1 = 清杂优先。只对队友；队长与没有编队时恒为 0
func prio_mode() -> int:
	if bool(get("is_leader")):
		return 0
	var sq = g.get("squad")
	return int(sq.priority) if sq != null else 0


## Boss 优先档要不要护主：队长 / 没有编队时照旧护主；队友在 command/boss_rush 开时全队集火、不护主（docs/114 §15）
func prio_mode_guard() -> bool:
	if bool(get("is_leader")) or g.get("squad") == null:
		return true
	return preload("res://scripts/core/balance.gd").v("command/boss_rush", 1.0) <= 0.0


## 指挥优先级的统一排序：攻击选敌（nearest_enemies）与突击走位选敌（character.roam_target）共用，两边口径一致。
## cands = [[敌人, 得分], …]，得分越小越优先、按得分升序排好（攻击侧 = 离 origin 的距离，走位侧 = 离队尾的距离等）；返回重排后的敌人数组。
## 0 Boss 优先：第一个是 Boss / 部件就不动；否则得分最小的可受击 Boss 提到最前；ai/boss_focus 关、或队长 ai/boss_focus_guard 内有非 Boss 贴脸（护主）时不提。
##   护主只留给队长自己的选敌（prio_mode_guard）：队友全队集火（command/boss_rush，10-27 用户），不再因小怪贴近队长让开 Boss。
## 1 清杂优先：杂兵（非 Boss / 精英 / 部件）在前，按周围 PRIO_DENSE_R 内的杂兵数（含自己，封顶 PRIO_DENSE_CAP）由多到少、同数按得分；
##   密集度只在得分最小的 PRIO_POOL 个杂兵里算；没有杂兵保持原顺序。不抽随机数，同分按原次序（稳定）
const PRIO_DENSE_R := 90.0
const PRIO_DENSE_CAP := 6
const PRIO_POOL := 24

func prio_order(cands: Array, mode: int) -> Array:
	var out: Array = []
	for c in cands:
		out.append(c[0])
	if out.size() <= 1:
		return out
	if mode == 0:
		if out[0].boss or out[0].get("part", false):
			return out
		var BalS = preload("res://scripts/core/balance.gd")
		if BalS.v("ai/boss_focus", 1.0) <= 0.0:
			return out
		var best = null
		var bs := INF
		for c in cands:
			if c[1] < bs and focusable_boss(c[0]):
				bs = c[1]
				best = c[0]
		if best == null:
			return out
		if prio_mode_guard():
			var guard: Array = g.enemies_sys.nearest(1, BalS.v("ai/boss_focus_guard", 60.0), g.ppos)
			if not guard.is_empty() and not guard[0].boss:
				return out   # 小怪贴着主控：先护主，不强制打 Boss（只剩队长自己 / 关了集火时）
		out.erase(best)
		out.push_front(best)
		return out
	var mobs: Array = []   # [敌人, 得分, 原次序]
	var rest: Array = []
	for i in cands.size():
		var e = cands[i][0]
		if prio_rank(e, 1) == 0 and mobs.size() < PRIO_POOL:
			mobs.append([e, cands[i][1], i])
		else:
			rest.append(e)
	if mobs.is_empty():
		return out
	var r2: float = PRIO_DENSE_R * PRIO_DENSE_R
	var keyed: Array = []
	for m in mobs:
		var c := 0
		for m2 in mobs:
			if m[0].pos.distance_squared_to(m2[0].pos) <= r2:
				c += 1
				if c >= PRIO_DENSE_CAP:
					break
		keyed.append([c, m[1], m[2], m[0]])
	keyed.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and (a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
	var res: Array = []
	for k in keyed:
		res.append(k[3])
	return res + rest


## 该敌人在优先级 mode 下是不是偏好档位（0 = 偏好）：Boss 优先 = 可受击的 Boss；清杂优先 = 杂兵（非 Boss / 精英 / 部件）
func prio_rank(e: Dictionary, mode: int) -> int:
	if mode == 0:
		return 0 if focusable_boss(e) else 1
	return 1 if (e.boss or e.elite or e.get("part", false)) else 0


## Boss 优先认的 Boss：打得动的 Boss（hittable：活着、没假死、不无敌、没在潜地 / 闸门无敌 / 阶段护盾 / 自己挡伤害）
func focusable_boss(e: Dictionary) -> bool:
	return e.boss and hittable(e)


## 射程内随机一名敌人（docs/108 F4，持续攻击 target: random）：入选条件同 nearest_enemies（活着、距离 < max_dist），
## 但不排序、不做 Boss 优先；有候选时只抽一次 g.rng。没有候选返回空字典
func random_enemy(max_dist: float, origin: Vector2 = Vector2.INF) -> Dictionary:
	var c: Array = g.enemies_sys.in_range(max_dist, origin)
	var ch: Array = c.filter(func(e): return hittable(e))
	if not ch.is_empty():
		c = ch   # 打不动的不抽（只剩它们时照旧）
	return {} if c.is_empty() else c[g.rng.randi_range(0, c.size() - 1)]


## 地形阻挡（terrain/aim_los，10-13 用户批准）：直线弹干员自动选目标——同 nearest_enemies，但从 from（缺省 = 干员自己）
## 到目标的连线穿过景物底座的排到后面；全被挡时就是原来的最近目标。无景物主题 / 旋钮关 = nearest_enemies 原样
func los_targets(n: int, max_dist: float, origin: Vector2 = Vector2.INF, from: Vector2 = Vector2.INF) -> Array:
	if not g.map.tb_aim or not g.map.blocks():
		return nearest_enemies(n, max_dist, origin)
	return los_sort(nearest_enemies(n + 8, max_dist, origin), n, from)


## 候选 cands（已按优先顺序排好）里先取视线内的，凑不够 n 个再按原顺序补被挡的；返回至多 n 个
func los_sort(cands: Array, n: int, from: Vector2 = Vector2.INF) -> Array:
	if cands.is_empty() or not g.map.tb_aim or not g.map.blocks():
		return cands.slice(0, n)
	var o: Vector2 = (get("pos") if from == Vector2.INF else from)
	if o == Vector2.INF:
		return cands.slice(0, n)
	var vis: Array = []
	var hid: Array = []
	for e in cands:
		if vis.size() >= n:
			break
		if g.map.segment_blocked(o, e.pos):
			hid.append(e)
		else:
			vis.append(e)
	if vis.size() < n:
		vis.append_array(hid.slice(0, n - vis.size()))
	return vis


## 场上可受击的 Boss（每帧缓存一次）：不在假死（coma）/ 无敌（invuln、gate_inv）/ 潜地（under）
var _fb_frame := -1
var _fb_list: Array = []

func _focus_bosses() -> Array:
	if _fb_frame == g.frame_n:
		return _fb_list
	_fb_frame = g.frame_n
	_fb_list = []
	for e in g.enemies:
		if focusable_boss(e):
			_fb_list.append(e)
	if g.has_meta("boss_decoys"):
		_fb_list.append_array(g.get_meta("boss_decoys"))   # 泡影二幕幻影（docs/142b §3.5）：和真身一起比远近，不替玩家认真身
	return _fb_list


## 最近的 n 个敌人，不带 Boss 优先（nearest_enemies 会把 Boss 提前；手动瞄准 / 落点要纯按距离）
func nearest_raw(n: int, max_dist: float, origin: Vector2 = Vector2.INF) -> Array:
	return g.enemies_sys.nearest(n, max_dist, origin)


## 空间网格查询：排除友方，返回 pos 周围 radius 内的敌人下标（g.enemies[i]，可能包含已死亡的，调用方自己判断 e.dead）
func query_ids(pos: Vector2, radius: float) -> Array:
	return g.enemies_sys.query(pos, radius)


## 扇形内的敌人（origin 为圆心，ang 朝向，half 半角）
func arc_targets(origin: Vector2, ang: float, half: float, radius: float) -> Array:
	return g.enemies_sys.arc_hit(origin, ang, half, radius)


## origin 周围 radius 内敌人最密处（没有敌人返回 Vector2.INF）
func densest_point(radius: float, origin: Vector2 = Vector2.INF) -> Vector2:
	return g.enemies_sys.densest_point(radius, origin)


# ---------------------------------------------------------------- 伤害 / 治疗

## 登记这一击的伤害来源（结算统计、藏品触发按来源分类）；在 deal_damage 之前调用
func log_hit(src: String, extra_tags: Array = []) -> void:
	g.combat.hit(src, extra_tags)


## 给敌人击退冲量（docs/101 B7：统一入口 enemies_sys.apply_kb，失重倍率在那里乘）；wl = false：调用方已按失重算过
func apply_kb(e: Dictionary, v: Vector2, wl := true) -> void:
	g.enemies_sys.apply_kb(e, v, wl)


## 控制状态统一入口（docs/101 §7.3.10）：转发 enemies_sys，语义见 run/enemies.gd
func add_cc(e: Dictionary, stun := -INF, slow := -INF, kind := "") -> void:
	g.enemies_sys.add_cc(e, stun, slow, kind)


## 成长节点（docs/202）的控制统一走这里：同一敌人 growth_nodes/cc_dr_window 秒内第二次受控，时长 × growth_nodes/cc_dr_mult（缺省 3 秒 / 0.5），
## 避免叠控把怪锁死。只对 stun 型（眩晕 / 定身 / 停顿 / 束缚 / 浮空）生效，减速不递减；旋钮 data/balance.json growth_nodes 段（--bal=growth_nodes/cc_dr_mult=1 即关）。
## 老节点和老技能仍直接 add_cc（基线不变）；docs/202 的新节点一律用本函数。
func add_cc_growth(e: Dictionary, stun := -INF, slow := -INF, kind := "") -> void:
	if stun > 0.0:
		var win: float = _BalG.v("growth_nodes/cc_dr_window", 3.0)
		if g.t - float(e.get("gcc_t", -99.0)) < win:
			stun *= _BalG.v("growth_nodes/cc_dr_mult", 0.5)
		e["gcc_t"] = g.t
	g.enemies_sys.add_cc(e, stun, slow, kind)


func set_air(e: Dictionary, h: float, hold_kb := false) -> void:
	g.enemies_sys.set_air(e, h, hold_kb)


func hold_at(e: Dictionary, p: Vector2) -> void:
	g.enemies_sys.hold_at(e, p)


func nudge(e: Dictionary, delta: Vector2) -> void:
	g.enemies_sys.nudge(e, delta)


func set_aggro(e: Dictionary, p: Vector2) -> void:
	g.enemies_sys.set_aggro(e, p)


## 对敌人造成伤害（走护甲、易伤、藏品倍率、击杀结算）
func deal_damage(e: Dictionary, dmg: float) -> void:
	var hp_before: float = e.hp
	var feedback_source: String = g.hit.get("src", "")
	g.combat.damage(e, dmg, g.hit)   # 门面：log_hit 设好的当前描述符显式传进去（docs/101 B7 ⑤）
	if float(e.hp) < hp_before:
		g.vfx.contact(str(get("id")), e, get("pos"), feedback_source)


## 治疗主控（src 进治疗统计）
func heal_leader(v: float, src: String = "其他", sub: String = "") -> void:
	g.combat.heal(v, src, sub)   # sub：遥测子项（docs/88，「常驻 / 技能」等），不进 heal_log


## 属性块变动后立即刷新 game.gd 的缓存变量（stats.add 之后需要当帧生效时调用）
func refresh_stats() -> void:
	g.sync_stats()


## 用对局随机数打乱（同 seed 可复现，docs/36）
func shuffle_rng(a: Array) -> void:
	g.shuffle(a)


# ---------------------------------------------------------------- 灯火

func lamp_radius() -> float:
	return g.lamp_r()


func lamp_sp() -> float:
	return g._lamp_sp()


# ---------------------------------------------------------------- 特效 / 提示


## 统一命中顿帧与落地碎屑，节流和预算由 VFX 模块处理。
func impact_pause(seconds: float) -> void:
	g.vfx.impact_pause(seconds)


func ground_dust(at: Vector2, radius := 22.0, count := 7) -> void:
	g.vfx.ground_dust(at, radius, count)

## 播放一次性特效帧条（V6_FRAMES 注册的 fx_*）；贴图缺失返回 false，调用方可退回程序特效
func spawn_fx_sprite(name: String, pos: Vector2, scale: float = -1.0, ang := 0.0, flip := false, bottom := false, col := Color.WHITE) -> bool:
	return g.vfx.fx_sprite(name, pos, g.PX if scale < 0.0 else scale, ang, flip, bottom, col)


## 旧式整条动画特效（跟随可选）
func play_anim_fx(name: String, pos: Vector2, dur: float, scale: float = -1.0, follow := false) -> bool:
	return g.vfx.anim(name, pos, dur, g.PX if scale < 0.0 else scale, follow)


## 挥砍弧光（普攻 / 技能的刀光）
func slash_fx(origin: Vector2, ang: float, half: float, radius: float, col: Color, tex_name := "slash", life := 0.22) -> void:
	g.vfx.slash_fx(origin, ang, half, radius, col, tex_name, life)


## 刀光贴图名（按强化状态选 base / awaken / mirage）
func slash_tex_name(kind := "base") -> String:
	return g.vfx.slash_tex(kind)


## 敌人受击闪白 / 火花
func enemy_hit_fx(e: Dictionary, dir := Vector2.ZERO) -> void:
	g.vfx.hit_fx(e, dir)


## 方向性火花
func sparks(pos: Vector2, dir: Vector2, col: Color, n: int, spd: float) -> void:
	g.vfx.sparks(pos, dir, col, n, spd)


## 飘字
func float_text(pos: Vector2, text: String, col: Color, size := 14) -> void:
	g.vfx.add_text(pos, text, col, size)


## 屏幕中上方横幅：干员技能名等提示一律最低优先级（vfx 横幅队列：有横幅在播时直接丢掉，不挤掉精英出现等局内事件）
func show_banner(text: String) -> void:
	g.vfx.show_banner(text, 0)


## 屏幕震动（强度 0–1，受设置里的震动开关缩放）
func screen_shake(a: float) -> void:
	g.vfx.shake_screen(a)


## HUD 技能栏条目（HUD 与图鉴读取）
func skill_item(i: int) -> Dictionary:
	return g.show_screen.skill_item(self, i)


# ---------------------------------------------------------------- 绘制（只能在 draw_* 回调里调用）

## 帧条绘制（按中心 / anchor 定位）
func draw_spr(name: String, frames: int, frame: int, pos: Vector2, scale: float = -1.0, flip := false, col := Color.WHITE, anchor := Vector2(0.5, 0.5), sq := Vector2.ONE) -> void:
	_cv_flush()
	g.vfx.spr(name, frames, frame, pos, g.PX if scale < 0.0 else scale, flip, col, anchor, sq)


## 旋转帧条绘制（支持 @2x 贴图）
func draw_spr_rot(name: String, frame: int, pos: Vector2, ang: float, scale: float = -1.0, col := Color.WHITE, anchor_px := Vector2(-1, -1), flip := false) -> void:
	_cv_flush()
	g.vfx.spr_rot(name, frame, pos, ang, g.PX if scale < 0.0 else scale, col, anchor_px, flip)


## 合批中直接往 g 上画（贴图包装、UI.diamond 等）之前：先把攒下的几何提交（保持层序），并把当前变换下发给 g
func _cv_flush() -> void:
	if cv != g and cv.active:
		cv.sync()
		cv.touch()   # 接下来的贴图画法可能改掉 g 的变换（画完置单位矩阵），下次按「未知」重新下发


## 菱形（同 UI.diamond，走 cv 合批）
func draw_diamond(c: Vector2, rad: float, fill: Color, border := Color(0, 0, 0, 0)) -> void:
	var p := PackedVector2Array([c + Vector2(0, -rad), c + Vector2(rad, 0), c + Vector2(0, rad), c + Vector2(-rad, 0)])
	cv.draw_colored_polygon(p, fill)
	if border.a > 0.0:
		p.append(p[0])
		cv.draw_polyline(p, border, 1.0)


## 画到另一个 CanvasItem 上（HUD 图标等）
func draw_spr_on(ci: CanvasItem, name: String, frames: int, frame: int, pos: Vector2, scale: float = -1.0) -> void:
	g.vfx.spr_on(ci, name, frames, frame, pos, g.PX if scale < 0.0 else scale)


## 按脚底锚点画角色帧（剪影、残影用）
func draw_sprite_at(pos: Vector2, flip: bool, col: Color, frame: int, tx: Texture2D, hf: int, foot_off: float, sc := 1.0) -> void:
	_cv_flush()
	g.world.draw_sprite_at(pos, flip, col, frame, tx, hf, foot_off, sc)
