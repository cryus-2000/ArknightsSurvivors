## 子弹出现 / 消失画面（用户 10-27「子弹的出现和消失都要有对应的动画或者粒子效果，开销自己想办法」）。纯画面：只读弹表、只往弹字典里写
## 下划线开头的画面字段（_bid 观察序号、_bt 首见时刻；_die 由结算处标消失原因），不改任何判定量，同 seed TRACE 不变；随机只用 g.vrng。
##
## 怎么接：world.draw_world 开头调 frame()，按渠道观察弹表（敌弹 g.ebullets、我方 g.bullets，能天使等干员自管的弹由各段画弹时调 observe）：
##   新出现的弹记 _bt → 绘制处乘 k(b)（0.09 秒由小到大、略过冲回 1）并叠亮芯闪（draw_top）；同帧同处成批出现（环形弹幕）合成一个出膛环 + 少量颗粒，不逐弹发；
##   上一帧还在、这一帧不在（或 life <= 0）的弹按原因出消失画面：
##     hit / rock / block / pop（命中、撞景物、被友方挡下、未标原因的突然消失）= 白芯一闪 + 本色爆散颗粒（Boss 弹 6、大弹 8、普通 4、景物 3）；
##     expire（life 自然耗尽）= 缩小淡出 + 2 颗冷却颗粒；
##     cancel / clear（干员消弹 cancel_in、清屏 / 演出清弹：仍有寿命却被移出弹表）= 统一溶解：缩小褪成冷白 + 向上飘的颗粒，按离队长的距离依次扫过，
##       超过同帧颗粒名额的按距离抽稀（远的只做缩放淡出）；
##     eaten（读条光圈吞弹，已有 eat_fx）、出界（没有出界消失：弹只按寿命走）不出画面。
## Boss 覆盖：set_hook(src_type, Callable(b, reason, pos) -> bool)，返回 true = 这只 Boss 自己画了，公共层不画；
##   set_spawn_hook(src_type, Callable(b, pos) -> bool) 同理管出现。弹自己带 hit_fx（专属命中帧条）或是酸团（落地溅开）时命中 / 到期不再叠公共画面。
## 开销：颗粒走 fx_grains（docs/136），另有本层令牌桶（render/bullet_fx_rate 每秒、render/bullet_fx_burst 攒量，手机网页再乘 grains.adapt_k），
##   且颗粒层已用到上限的 85% 时不再要；要不到就只剩缩放 / 淡出（几个合批三角形）。低画质、关光学观感、fx/bullet_grains = 0 时只做缩放淡出；
##   render/bullet_fx = 0 整层关（--bulfxab=N 同局轮换量帧，--perf 分 /b1 /b0）
## Boss 弹粒子化（docs/206，用户 10-31「没有粒子感」）：Boss 弹（b.boss）命中 / 到期 / 被消不再整颗淡出，改播预烘焙迸散帧条 fx_px_bpop
##   （tools/imagegen/pxburst.py --boss，8–14 颗、减速、冷却变暗；3 行花样 + 左右镜像），按弹专属色着色；飞行时身后贴拖尾帧条 fx_px_btrail
##   （4 帧循环、按速度拉长、沿速度转向；同屏 Boss 弹 > render/btrail_thin（100）颗时隔颗画；伊祖米克 130 弹实测 p95 0.4 ms（探针含放大））。都是贴图矩形，不走逐颗粒循环；
##   render/boss_pop = 0 / render/boss_trail = 0 各自关回旧画面
## 贴图颗粒全部走本层贴图三角批（_tq 攒四边形，_tq_flush 按贴图一次 canvas_item_add_triangle_array，同 TriBatch 的提交方式；
##   perf-60fps 10-31：别每颗弹单独 draw_texture），不用 draw_set_transform
## Boss 激光（kp_beam 帧条光束、bbeam 粗光束、敌方 tracer）：beam_px 沿光束每 22 px 贴一格 fx_px_bpop 后段帧（错相循环 = 边缘颗粒持续飘出），
##   收束最后 0.07 秒整条按 _pop 碎成颗粒（从起点往末端依次）；render/boss_beam_px = 0 关
## Boss 地面招式落地（telegraph.warn_resolve：Boss 的圆形落点圈结算那一刻）：ground_burst 按圈半径播一次 fx_px_burst1/2（大号迸散），
##   专属色着色、画在弹体之下；同屏最多 GROUND_MAX 个；render/boss_ground_px = 0 关
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")

const SPAWN_T := 0.09        # 出现动画时长（秒）
const GHOST_MAX := 220       # 同屏消失残影上限（超了新的直接不画）
const CLUSTER := 40.0        # 同帧出现按 40 世界像素格聚成一簇
const EB_LIFT := Vector2(0, -16)   # 敌弹画在脚下 16 像素上方（同 world._ebp）
const BossBeam = preload("res://scripts/render/boss_beam.gd")
const POP := "fx_px_bpop"    # 8 帧 × 3 行，1 纹素 = 2 世界像素
const POP_T := 0.45
const POP_MAX := 400
const TRAIL := "fx_px_btrail"   # 4 帧循环，弹头在帧的右端中心
const GROUND := ["fx_px_burst1", "fx_px_burst2"]   # 8 帧 / 0.9 秒，帧 360 纹素见方（颗粒最远约 180 纹素）
const GROUND_T := 0.9
const GROUND_MAX := 24

var g
var w   # render/world.gd
var clock := 0.0             # 画面时钟：按渲染帧间隔走（受 Engine.time_scale 影响；bosstest 的 g.t 冻结也照走）
var off := false             # --bulfxab 同局轮换：true = 这一段整层关（旧画面）
var _id := 0
var _prev := {}              # 渠道名 → {_bid: 弹字典}
var _young: Array = []       # 还在出现动画里的弹 [弹字典, 画面偏移, 半径, 颜色]
var ghosts: Array = []       # [种类, 位置, 半径, 颜色, 已过, 时长, 延迟]；种类 0 闪 / 1 缩 / 2 溶 / 3 出膛环
var pops: Array = []         # Boss 弹迸散 [位置, 颜色, 已过, 延迟, 行, 镜像]
var grounds: Array = []      # Boss 落地迸散 [位置, 颜色, 已过, 半径, 哪张, 镜像]
var _spawns: Array = []      # 本帧新出现 [起点（画面位置）, 方向, 颜色, 半径, 弹字典, 渠道]
var _dq: Array = []          # 本帧待溶解 [位置, 半径, 颜色]
var hooks := {}
var spawn_hooks := {}
var _tok := 0.0
var _tok_us := 0
var _on := true
var _was_on := false
var _silent := false
var _grains_ok := false
var stat_spawn := 0          # 计数（--perf 之外的自测用）
var stat_die := 0
var stat_why := {}           # 消失原因 → 次数（只计画面里出了效果的）
var stat_grains := 0         # 实际发出的颗粒数


func _init(game, world) -> void:
	g = game
	w = world


## Boss 覆盖消失画面：f(b, reason, pos) -> bool（true = 已自己画）
func set_hook(src_type: String, f: Callable) -> void:
	hooks[src_type] = f


## Boss 覆盖出现画面：f(b, pos) -> bool
func set_spawn_hook(src_type: String, f: Callable) -> void:
	spawn_hooks[src_type] = f


## 每帧（world.draw_world 开头）：推进时钟、残影，观察敌弹 / 我方弹
func frame() -> void:
	var dt: float = clampf(g.get_process_delta_time(), 0.0, 0.1)
	clock += dt
	_on = not off and Bal.v("render/bullet_fx", 1.0) > 0.0
	var gr = _grains()
	_grains_ok = gr != null and Cfg.quality != "low" and Bal.v("fx/bullet_grains", 1.0) > 0.0
	var k := 0
	for gh in ghosts:
		gh[4] = float(gh[4]) + dt
		if float(gh[4]) < float(gh[5]) + float(gh[6]):
			ghosts[k] = gh
			k += 1
	ghosts.resize(k)
	k = 0
	for pp in pops:
		pp[2] = float(pp[2]) + dt
		if float(pp[2]) < POP_T + float(pp[3]):
			pops[k] = pp
			k += 1
	pops.resize(k)
	k = 0
	for gg in grounds:
		gg[2] = float(gg[2]) + dt
		if float(gg[2]) < GROUND_T:
			grounds[k] = gg
			k += 1
	grounds.resize(k)
	if not _on:
		_young.clear()
		_prev.clear()
		_was_on = false
		return
	_silent = not _was_on   # 刚从关切回开（--bulfxab 轮换 / 开关）：这一帧只认弹不出画面，免得把在飞的弹全当新弹
	_was_on = true
	observe("e", g.ebullets, "pos", true, false)
	observe("p", g.bullets, "pos", false, true)
	_silent = false
	flush()


## 观察一张弹表。ch 渠道名（各表独立）；pk 位置字段（"pos" / "p"）；enemy 敌弹（画在 16 像素上方、敌弹色）；
## abrupt_own：未标原因的突然消失（life 恰为 0）当作「命中且有自己的命中画面」，公共层不画（我方弹：命中都有爆炸 / 命中帧条）
func observe(ch: String, arr: Array, pk := "pos", enemy := false, abrupt_own := false, col := Color(0, 0, 0, 0)) -> void:
	if not _on:
		return
	var prev: Dictionary = _prev.get(ch, {})
	var cur := {}
	for b in arr:
		var id: int = int(b.get("_bid", -1))
		if id >= 0 and prev.has(id) and is_same(prev[id], b):
			if float(b.life) > 0.0:
				cur[id] = b
			continue
		if float(b.life) <= 0.0:
			continue   # 生出即消失（同一帧内）：不出画面
		_id += 1
		b["_bid"] = _id
		cur[_id] = b
		if _silent or not _prev.has(ch):
			b["_bt"] = clock - SPAWN_T   # 渠道第一次观察（开局 / 刚打开）：已在飞的弹不补出现动画
			continue
		b["_bt"] = clock
		_spawn(b, pk, enemy, ch, col)
	if _silent:
		_prev[ch] = cur
		return
	for id in prev:
		if not cur.has(id):
			_die(prev[id], pk, enemy, abrupt_own, col)
	_prev[ch] = cur
	if ch == "e" or ch == "p":
		return
	# 干员自管弹表：本帧就结算（敌弹 / 我方弹在 flush 里统一结算）
	flush()


## 出现动画的缩放（绘制处乘在半径 / 贴图缩放上）：0.3 → 1.15（前 70%）→ 1.0；不在动画里 = 1
func k(b: Dictionary) -> float:
	var t0 = b.get("_bt")
	if t0 == null or not _on:
		return 1.0
	var u: float = (clock - float(t0)) / SPAWN_T
	if u >= 1.0:
		return 1.0
	if u < 0.7:
		return lerpf(0.3, 1.15, u / 0.7)
	return lerpf(1.15, 1.0, (u - 0.7) / 0.3)


func _col(b: Dictionary, enemy: bool, col: Color) -> Color:
	if col.a > 0.0:
		return col
	if enemy:
		if g.optical_on and g.optical != null:
			return g.optical.eb_col(b)
		match str(b.get("kind", "orb")):
			"acid":
				return Color(0.6, 1.4, 0.4)
			"nova":
				var bc = b.get("col")
				return bc if bc is Color else Color(1.3, 0.55, 1.7)
			"nerve":
				return Color(1.4, 1.25, 0.45)
		return Color(1.0, 0.35, 0.65)
	if g.optical != null and g.optical.particles != null:
		return g.optical.particles._bullet_col(b)
	var fc = b.get("fx_col")
	return fc if fc is Color else Color(1.0, 0.75, 0.4)


func _vpos(b: Dictionary, pk: String, enemy: bool) -> Vector2:
	return (b[pk] as Vector2) + (EB_LIFT if enemy else Vector2.ZERO)


func _r(b: Dictionary) -> float:
	return clampf(float(b.get("r", 5.0)), 3.0, 14.0)


func _spawn(b: Dictionary, pk: String, enemy: bool, ch: String, col: Color) -> void:
	stat_spawn += 1
	var p: Vector2 = _vpos(b, pk, enemy)
	var st: String = str(b.get("src_type", ""))
	if st != "" and spawn_hooks.has(st) and bool(spawn_hooks[st].call(b, p)):
		return
	if str(b.get("kind", "")) == "boss_blade" or b.get("hidden", false):
		return   # 骑士飞刃有自己的画法（vfx.boss_blade）
	if not w.view_rect(48.0).has_point(p):
		return
	var c: Color = _col(b, enemy, col)
	var r: float = _r(b)
	var v: Vector2 = b.get("vel", b.get("v", Vector2.ZERO))
	_young.append([b, EB_LIFT if enemy else Vector2.ZERO, r, c, pk])
	_spawns.append([p, v.normalized() if v.length_squared() > 1.0 else Vector2.RIGHT, c, r])


func _die(b: Dictionary, pk: String, enemy: bool, abrupt_own: bool, col: Color) -> void:
	stat_die += 1
	var reason: String = str(b.get("_die", ""))
	var lf: float = float(b.life)
	if reason == "":
		reason = "clear" if lf > 0.0 else ("expire" if lf < 0.0 else "pop")
	if reason == "eaten" or (reason == "pop" and abrupt_own):
		return
	var p: Vector2 = _vpos(b, pk, enemy)
	if not w.view_rect(24.0).has_point(p):
		return
	var st: String = str(b.get("src_type", ""))
	if st != "" and hooks.has(st) and bool(hooks[st].call(b, reason, p)):
		return
	if reason in ["hit", "expire"] and (str(b.get("hit_fx", "")) != "" or str(b.get("kind", "")) == "acid"):
		return   # 专属命中帧条 / 酸团溅开已经是消失画面
	var c: Color = _col(b, enemy, col)
	var r: float = _r(b)
	stat_why[reason] = int(stat_why.get(reason, 0)) + 1
	var bp: bool = b.get("boss", false) and _pop_ok()
	if bp and reason != "cancel" and reason != "clear":
		_pop(p, c)
		return
	match reason:
		"cancel", "clear":
			_dq.append([p, r, c, bp])
		"expire":
			_ghost(1, p, r, c, 0.12)
			_burst("bul_cool", p, c, 2)
		_:
			_ghost(0, p, r, c, 0.1)
			var n: int = 3 if reason == "rock" else (8 if r >= 9.0 else (6 if b.get("boss", false) else 4))
			_burst("bul_pop", p, c, n)


## 本帧结算：出现（按簇合批）+ 溶解（按距离扫过、超名额抽稀）
func flush() -> void:
	if not _spawns.is_empty():
		var cl := {}
		for s in _spawns:
			var key := Vector2i(floori((s[0] as Vector2).x / CLUSTER), floori((s[0] as Vector2).y / CLUSTER))
			if not cl.has(key):
				cl[key] = []
			cl[key].append(s)
		for key in cl:
			var ss: Array = cl[key]
			if ss.size() == 1:
				var s: Array = ss[0]
				_burst("bul_spawn", s[0], s[2], 2, s[1])
				continue
			# 成批出现（环形弹幕 / 散射）：一圈出膛环 + 至多 8 颗沿弹道的颗粒（均匀挑几发的方向）
			var ctr := Vector2.ZERO
			for s in ss:
				ctr += s[0]
			ctr /= float(ss.size())
			var s0: Array = ss[0]
			_ghost(3, ctr, clampf(8.0 + float(ss.size()) * 1.2, 12.0, 40.0), s0[2], 0.12)
			var m: int = mini(8, ss.size())
			var gv: int = _take(m)
			for i in gv:
				var s: Array = ss[i * ss.size() / m]
				_push("bul_spawn", s[0], s[1], s[2])
		_spawns.clear()
	if not _dq.is_empty():
		var pp: Vector2 = g.ppos + EB_LIFT
		_dq.sort_custom(func(a, b): return (a[0] as Vector2).distance_squared_to(pp) < (b[0] as Vector2).distance_squared_to(pp))
		var gn: int = 40 if g.optical == null or g.optical.grains == null or g.optical.grains.level >= 2 else 24
		var sweep: float = Bal.v("render/bullet_fx_sweep", 1600.0)   # 扫过速度（世界像素 / 秒）：离队长近的先溶
		for i in _dq.size():
			var q: Array = _dq[i]
			var d: float = minf(0.25, (q[0] as Vector2).distance_to(pp) / sweep) if _dq.size() > 6 else 0.0
			if q[3]:
				_pop(q[0], q[2], d)
				continue
			_ghost(2, q[0], q[1], q[2], 0.16, d)
			if i < gn:
				_burst("bul_dis", q[0], q[2], 3, Vector2.UP, d)
		_dq.clear()


func _ghost(kind: int, p: Vector2, r: float, c: Color, dur: float, delay := 0.0) -> void:
	if ghosts.size() >= GHOST_MAX:
		return
	ghosts.append([kind, p, r, c, 0.0, dur, delay])


func _pop_ok() -> bool:
	return Bal.v("render/boss_pop", 1.0) > 0.0 and w._lazy_tex(POP) != null


func _pop(p: Vector2, c: Color, delay := 0.0) -> void:
	if pops.size() >= POP_MAX:
		return
	pops.append([p, c, 0.0, delay, g.vrng.randi_range(0, 2), g.vrng.randf() < 0.5])


## Boss 落地迸散（telegraph.warn_resolve 调，纯画面；随机只用 g.vrng）
func ground_burst(p: Vector2, r: float, c: Color) -> void:
	if not _on or Bal.v("render/boss_ground_px", 1.0) <= 0.0 or grounds.size() >= GROUND_MAX or r < 12.0:
		return
	if not w.view_rect(r + 40.0).has_point(p):
		return
	grounds.append([p, c, 0.0, r, g.vrng.randi_range(0, 1), g.vrng.randf() < 0.5])


## 落地迸散（world 画敌弹之前，压在弹体之下）：颗粒最远处约等于落点圈半径
func draw_grounds() -> void:
	for gg in grounds:
		var t: Texture2D = w._lazy_tex(GROUND[int(gg[4])])
		if t == null:
			continue
		var fw: float = t.get_width() / 8.0
		var fh: float = float(t.get_height())
		var f: int = mini(7, int(float(gg[2]) / GROUND_T * 8.0))
		var sz := Vector2(fw, fh * float(g.combat.GROUND_Y)) * (float(gg[3]) * 2.2 / fw)   # 压扁成地面透视（同落点圈）
		var c: Color = gg[1]
		_tq_rect(t, (gg[0] as Vector2) - sz * 0.5, sz, Rect2(float(f) * fw, 0.0, fw, fh), gg[5], Color(c.r * 1.15, c.g * 1.15, c.b * 1.15, 0.9))
	_tq_flush()


## ---- 贴图三角批：同一张贴图的四边形攒进成员数组（Packed 数组是值类型，只有成员能原地追加），换贴图或 _tq_flush 时一次提交；
## 提交时画布变换须为单位矩阵（本层不改变换）
var _tq_t: Texture2D = null
var _tq_p := PackedVector2Array()
var _tq_c := PackedColorArray()
var _tq_u := PackedVector2Array()


## 四边形 p0..p3（左上、右上、右下、左下，对应源区 src 的四角）；flip = 左右镜像
func _tq(t: Texture2D, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, src: Rect2, flip: bool, col: Color) -> void:
	if t != _tq_t:
		_tq_flush()
		_tq_t = t
	var ts: Vector2 = t.get_size()
	var u0: float = src.position.x / ts.x
	var u1: float = src.end.x / ts.x
	if flip:
		var tu: float = u0
		u0 = u1
		u1 = tu
	var v0: float = src.position.y / ts.y
	var v1: float = src.end.y / ts.y
	_tq_p.append_array([p0, p1, p2, p0, p2, p3])
	_tq_u.append_array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1)])
	_tq_c.append_array([col, col, col, col, col, col])


func _tq_rect(t: Texture2D, pos: Vector2, sz: Vector2, src: Rect2, flip: bool, col: Color) -> void:
	_tq(t, pos, pos + Vector2(sz.x, 0.0), pos + sz, pos + Vector2(0.0, sz.y), src, flip, col)


func _tq_flush() -> void:
	if _tq_t != null and not _tq_p.is_empty():
		RenderingServer.canvas_item_add_triangle_array(g.get_canvas_item(), PackedInt32Array(), _tq_p, _tq_c, _tq_u, PackedInt32Array(), PackedFloat32Array(), _tq_t.get_rid())
	_tq_p = PackedVector2Array()
	_tq_c = PackedColorArray()
	_tq_u = PackedVector2Array()
	_tq_t = null


static func _hh(i: int) -> float:
	return fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)


## Boss 激光颗粒（world._draw_fx 画完 kp_beam / bbeam / 敌方 tracer 后调）：c = 光束本色、hw = 光束可见半宽
func beam_px(f: Dictionary, c: Color, hw: float) -> void:
	if not f.has("a") or not f.has("b"):
		return
	var left: float = float(f.max) - BossBeam.laser_el(f)
	beam_line(f, f.a, f.b, c, hw, float(f.max) - left, left < minf(0.07, float(f.max) * 0.3))


## 光束颗粒通用画法（伊莎玛拉统一光束 ishar_tell_draw 也调）：颗粒贴在两侧边缘往外飘（提亮一档免得和光束同色糊在一起）；
## closing = 收束那一刻：整条按 _pop 从起点往末端碎成颗粒（st 记一次，只碎一回）
func beam_line(st: Dictionary, a: Vector2, b: Vector2, c: Color, hw: float, el: float, closing: bool) -> void:
	if not _on or Bal.v("render/boss_beam_px", 1.0) <= 0.0:
		return
	var t: Texture2D = w._lazy_tex(POP)
	var L: float = a.distance_to(b)
	if t == null or L < 8.0:
		return
	var d: Vector2 = (b - a) / L
	var nr: Vector2 = d.orthogonal()
	var step := 22.0
	var n: int = mini(int(L / step) + 1, 60)
	var seed: int = int(absf(a.x * 7.0 + a.y * 13.0)) % 977
	c = c.lerp(Color.WHITE, 0.35)
	if closing:
		if not st.get("px_end", false):
			st["px_end"] = true
			for i in n:
				_pop(a + d * (float(i) + 0.5) * step + nr * (_hh(seed + i) - 0.5) * hw, c, 0.01 * float(i))
		return
	var fw: float = t.get_width() / 8.0
	var fh: float = t.get_height() / 3.0
	var sz := Vector2(fw * 2.0, fh * 2.0)
	for i in n:
		var h: float = _hh(seed + i)
		var ph: float = fposmod(el * 2.4 + h, 1.0)
		var fi: int = 2 + int(ph * 6.0)   # 只用后 6 帧（散开的颗粒），不要开头那团亮核
		var p: Vector2 = a + d * (float(i) + 0.5) * step + nr * (1.0 if i % 2 == 0 else -1.0) * (hw + 4.0 + 8.0 * h)
		_tq_rect(t, p - sz * 0.5, sz, Rect2(float(fi) * fw, float(i % 3) * fh, fw, fh), i % 2 == 1, Color(c.r * 1.2, c.g * 1.2, c.b * 1.2, 0.85))
	_tq_flush()


func _grains():
	if g.optical == null or g.optical.grains == null or not g.optical.grains.on():
		return null
	return g.optical.grains


## 本层颗粒令牌桶：要 n 颗，给 0..n（颗粒层已近上限 / 低画质 / 关粒子 = 0）
func _take(n: int) -> int:
	if not _grains_ok:
		return 0
	var gr = g.optical.grains
	if gr.pos.size() >= int(float(gr.budget()) * 0.85):
		return 0
	var now: int = Time.get_ticks_usec()
	var ak: float = float(gr.adapt_k)
	var rate: float = Bal.v("render/bullet_fx_rate", 700.0) * ak
	var cap: float = Bal.v("render/bullet_fx_burst", 160.0) * ak
	if _tok_us > 0:
		_tok = minf(cap, _tok + rate * float(now - _tok_us) / 1000000.0)
	else:
		_tok = cap
	_tok_us = now
	var give: int = mini(n, int(_tok))
	_tok -= float(give)
	stat_grains += give
	return give


func _burst(tpl: String, p: Vector2, c: Color, n: int, dir := Vector2.ZERO, delay := 0.0) -> void:
	var gv: int = _take(n)
	for i in gv:
		var d: Vector2 = dir if dir != Vector2.ZERO else Vector2.from_angle(TAU * (float(i) + g.vrng.randf()) / float(gv))
		g.optical.grains.push(tpl, p, d, c, delay)


func _push(tpl: String, p: Vector2, d: Vector2, c: Color) -> void:
	g.optical.grains.push(tpl, p, d, c)


## Boss 弹拖尾（world 画敌弹之前调，压在弹体之下）：沿速度方向贴 fx_px_btrail，按速度拉长；同屏多时隔颗


func draw_trails() -> void:
	if not _on or Bal.v("render/boss_trail", 1.0) <= 0.0:
		return
	var t: Texture2D = w._lazy_tex(TRAIL)
	if t == null:
		return
	var fw: float = t.get_width() / 4.0
	var fh: float = float(t.get_height())
	var vr: Rect2 = w.view_rect(48.0)
	var n := 0
	for b in g.ebullets:
		if b.get("boss", false):
			n += 1
	if n == 0:
		return
	var thin: bool = n > int(Bal.v("render/btrail_thin", 100.0))
	var fr0: int = int(clock * 14.0)
	for b in g.ebullets:
		if not b.get("boss", false) or b.get("hidden", false) or str(b.get("kind", "")) == "boss_blade" or float(b.life) <= 0.0:
			continue
		var id: int = int(b.get("_bid", 0))
		if thin and id % 2 == 1:
			continue
		var v: Vector2 = b.get("vel", b.get("v", Vector2.ZERO))
		var sp: float = v.length()
		if sp < 30.0:
			continue
		var p: Vector2 = (b.pos as Vector2) + EB_LIFT
		if not vr.has_point(p):
			continue
		var c: Color = _col(b, true, Color(0, 0, 0, 0))
		var d: Vector2 = v / sp
		var sx: float = 2.0 * clampf(sp / 200.0, 0.8, 1.8)   # 拖尾按速度拉长：120 速约 26 px、快弹到 58 px
		var o: Vector2 = p - d * (float(b.get("r", 5.0)) + 2.0)   # 从弹体可见边缘（r + 3）往后拖
		var ax: Vector2 = d * fw * sx
		var ay: Vector2 = d.orthogonal() * fh   # 纵向 1 纹素 = 2 世界像素：半高 fh
		_tq(t, o - ax - ay, o - ay, o + ay, o - ax + ay, Rect2(float((fr0 + id) % 4) * fw, 0.0, fw, fh), false, Color(c.r * 1.2, c.g * 1.2, c.b * 1.2, 0.9))
	_tq_flush()


## 弹体上层（world 画完敌弹之后）：Boss 弹迸散帧条 + 新弹亮芯闪 + 消失残影（后两者进 world 的无贴图批）
func draw_top() -> void:
	if not pops.is_empty():
		var t: Texture2D = w._lazy_tex(POP)
		if t != null:
			var fw: float = t.get_width() / 8.0
			var fh: float = t.get_height() / 3.0
			var sz := Vector2(fw * 2.0, fh * 2.0)
			for pp in pops:
				var el: float = float(pp[2]) - float(pp[3])
				if el < 0.0:
					continue
				var f: int = mini(7, int(el / POP_T * 8.0))
				var c: Color = pp[1]
				_tq_rect(t, (pp[0] as Vector2) - sz * 0.5, sz, Rect2(f * fw, int(pp[4]) * fh, fw, fh), pp[5], Color(c.r * 1.25, c.g * 1.25, c.b * 1.25, 1.0))
			_tq_flush()
	if not _on and ghosts.is_empty():
		return
	var k := 0
	for y in _young:
		var b: Dictionary = y[0]
		var u: float = (clock - float(b.get("_bt", -9.0))) / SPAWN_T
		if u >= 1.0 or float(b.life) <= 0.0:
			continue
		_young[k] = y
		k += 1
		var p: Vector2 = (b[y[4]] as Vector2) + (y[1] as Vector2)
		var r: float = float(y[2])
		var c: Color = y[3]
		var a: float = 1.0 - u
		w.tb_circle(p, r * (1.5 - 0.6 * u), Color(c.r, c.g, c.b, 0.35 * a))   # 本色晕
		w.tb_circle(p, maxf(1.5, r * 0.75 * a), Color(2.2, 2.2, 2.2, a))      # 亮芯闪
	_young.resize(k)
	for gh in ghosts:
		var el: float = float(gh[4]) - float(gh[6])
		var p: Vector2 = gh[1]
		var r: float = float(gh[2])
		var c: Color = gh[3]
		if el < 0.0:
			if int(gh[0]) == 2:   # 溶解等待扫到：原样留着（弹已移出弹表，由残影替它多停一会儿）
				w.tb_circle(p, r, Color(c.r, c.g, c.b, 0.9))
			continue
		var u: float = clampf(el / float(gh[5]), 0.0, 1.0)
		match int(gh[0]):
			0:   # 命中：白芯一闪外扩 + 本色细环
				w.tb_circle(p, r * (0.9 + 0.6 * u), Color(2.0, 2.0, 2.0, 1.0 - u))
				w.tb_ring(p, r * (1.2 + 1.4 * u), 1.5, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 1.0 - u))
			1:   # 到期：缩小淡出
				w.tb_circle(p, r * (1.0 - u), Color(c.r, c.g, c.b, 1.0 - 0.6 * u))
				w.tb_circle(p, r * 0.4 * (1.0 - u), Color(1.6, 1.6, 1.6, 1.0 - u))
			2:   # 溶解：缩小并褪成冷白
				var cc: Color = c.lerp(Color(0.85, 0.95, 1.1), u)
				w.tb_circle(p, r * (1.0 - 0.8 * u), Color(cc.r, cc.g, cc.b, 0.9 * (1.0 - u)))
				w.tb_ring(p, r * (1.0 + 0.5 * u), 1.0, Color(cc.r, cc.g, cc.b, 0.6 * (1.0 - u)))
			3:   # 出膛环：由小到大、淡出
				w.tb_ring(p, 4.0 + r * u, 2.0 - u, Color(c.r * 1.5, c.g * 1.5, c.b * 1.5, 0.9 * (1.0 - u)))
				if u < 0.5:
					w.tb_circle(p, 6.0 * (1.0 - u * 2.0), Color(2.0, 2.0, 2.0, 1.0 - u * 2.0))
	w.tb_flush()
