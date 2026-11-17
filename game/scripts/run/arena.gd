extends RefCounted
## 最终 Boss 场地（docs/38 §1.7 B1 第二批；docs/364 §7 从黑潮缩圈里拆出来，所有主题通用）：
## 最终 Boss 登场时 freeze(arena_r)：圈 3 秒内平滑变到场地半径；主控离新圈边不足 100（或在圈外）就把圆心往主控挪；
## 圈还没开始（zone_state == 0）时以主控为圆心新建。冻结后 zone_state = 3、zone_next_* 同步成场地，机器人读到的边界与实际一致。
## 圈的状态仍是 g.zone_c / zone_r / zone_next_* / zone_state / zone_frozen / zone_t（缩圈机制、机器人、画面共用）。
## 冻结那一刻按清单顺序调各主题机制的 on_arena_freeze(fresh)（缩圈重置阶段、溟痕清掉场地里的）。圈外伤害仍归主题机制（水月：黑潮）。
## 函数体从 mech_tide_zone.freeze_zone / _arena_step、combat.arena_clamp / mire_blocked 原样搬来。

const Game = preload("res://scripts/game.gd")
var g: Game
var from_c := Vector2.ZERO
var from_r := 0.0
var t := 0.0


func _init(game: Game) -> void:
	g = game


func freeze(r: float) -> void:
	var fresh: bool = g.zone_state == 0
	if fresh:
		g.zone_c = g.ppos
		g.zone_r = r + 400.0
	var c: Vector2 = g.zone_c
	var d: float = g.ppos.distance_to(c)
	if d > r - 100.0 and d > 0.001:
		c = g.ppos + (c - g.ppos) / d * (r - 100.0)
	from_c = g.zone_c
	from_r = g.zone_r
	t = 0.0
	g.zone_next_c = c
	g.zone_next_r = r
	g.zone_state = 3
	g.zone_t = 0.0
	g.zone_frozen = true
	for m in g.mechs:
		m.on_arena_freeze(fresh)


## 每帧（game._update_player，主题机制 on_player_tick 之前）：冻结后 3 秒把圈插值到场地
func step(dt: float) -> void:
	if not g.zone_frozen:
		return
	if t >= 3.0:
		return
	t = minf(t + dt, 3.0)
	var k := smoothstep(0.0, 1.0, t / 3.0)
	g.zone_c = from_c.lerp(g.zone_next_c, k)
	g.zone_r = lerpf(from_r, g.zone_next_r, k)


## 场地是禁生成圆区；最大半径与圆区相交（含相切）就禁止整片生成
func blocked(pos: Vector2, radius: float = 0.0) -> bool:
	return g.zone_frozen and pos.distance_squared_to(g.zone_next_c) <= pow(maxf(0.0, g.zone_next_r) + maxf(0.0, radius), 2.0)


## 把 Boss 本体、召唤物 / 落点的生成点约束在场地内、离圈边 ≥ margin；场地没冻结时原样返回
func clamp_point(p: Vector2, margin := 80.0) -> Vector2:
	if not g.zone_frozen:
		return p
	var lim: float = maxf(0.0, g.zone_next_r - margin)
	var v: Vector2 = p - g.zone_next_c
	return p if v.length() <= lim else g.zone_next_c + v.normalized() * lim
