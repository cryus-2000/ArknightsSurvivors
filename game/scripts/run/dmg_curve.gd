extends RefCounted
## 普通怪伤害曲线（docs/194，用户 10-29「整条曲线单调平滑、没有凹凸点和断崖，后期不再一下子暴毙」）。
## 一条按时间的目标曲线 T(t)（balance.json dmg_curve/knots：关键点 + 单调三次插值，Fritsch–Carlson / PCHIP），
## 口径 = 「当时刷怪池平均」的一下伤害：池平均基础伤害 × 时间倍率 × 密度 (1/density)^density_dmg_exp × 受伤 ref_taken − 平均护甲 ref_armor。
## 时间倍率 m(t) 按每个威胁档刷怪池的平均基础伤害归一，让池平均一下严格沿 T(t) 走；个体差异保留（狂奔者照样比骨海疼），档位换池时曲线不跳。
## 精英 ×elite_dmg_mult、大群、敌弹系数、Boss 不在这里动。

const Bal = preload("res://scripts/core/balance.gd")
const D = preload("res://scripts/data.gd")

static var _avg: Dictionary = {}   # 威胁档下标 -> 刷怪池平均基础伤害（只读数据，缓存）


static func enabled() -> bool:
	return Bal.v("dmg_curve/on", 1.0) > 0.0


## 难度校准的中后段削减（docs/200，10-30）：dmg_curve/mid_cut 比例，从 mid_from 秒起按平滑阶梯（smoothstep）削到 mid_to 秒，之后保持；
## mid_from 之前（前期伤害，用户亲定）不动。mid_cut 0 = 关
## 削得多时（如 0.22）削减斜率会超过曲线本身斜率、中段微微回落；用户要「单调平滑」（10-29，协调人 10-31 定 A），
## 所以削减段取「已过的最高值」：按 1 秒采样的累计最高值做线性插值，削减段之后取 max(当前值, 段内最高)，任意参数都单调不降
static var _mono_key := []
static var _mono: PackedFloat32Array = PackedFloat32Array()   # 削减段 [a, b] 每秒累计最高值


static func _cut_v(t: float, cut: float, a: float, b: float, sc: float) -> float:
	var x: float = clampf((t - a) / maxf(1.0, b - a), 0.0, 1.0)
	return target_raw(t) * sc * (1.0 - cut * x * x * (3.0 - 2.0 * x))


static func target(t: float) -> float:
	if Bal.v("growth/late_shape", 0.0) > 0.0:   # 后期形状原型的难度补偿（docs/248）：comp_from → comp_to 秒内平滑升到 × comp_dmg，之后保持
		var x: float = clampf((t - Bal.v("shape_lv/comp_from", 240.0)) / maxf(1.0, Bal.v("shape_lv/comp_to", 420.0) - Bal.v("shape_lv/comp_from", 240.0)), 0.0, 1.0)
		return _target0(t) * (1.0 + (Bal.v("shape_lv/comp_dmg", 1.0) - 1.0) * x * x * (3.0 - 2.0 * x))
	return _target0(t)


static func _target0(t: float) -> float:
	var cut: float = Bal.v("dmg_curve/mid_cut", 0.0)
	var sc: float = Bal.v("dmg_curve/scale", 1.0)   # 全程整体倍率（难度校准 10-31，缺省 1 = 不变）
	if cut <= 0.0:
		return target_raw(t) * sc
	var a: float = Bal.v("dmg_curve/mid_from", 180.0)
	var b: float = maxf(a + 1.0, Bal.v("dmg_curve/mid_to", 420.0))
	if t <= a:
		return target_raw(t) * sc
	var key := [cut, a, b, sc, Bal.sec("dmg_curve").get("knots", []).hash()]
	if key != _mono_key:
		_mono_key = key
		var n: int = int(ceil(b - a)) + 1
		_mono.resize(n)
		var m := -INF
		for i in n:
			m = maxf(m, _cut_v(minf(a + i, b), cut, a, b, sc))
			_mono[i] = m
	var n2: int = _mono.size()
	if t >= b:
		return maxf(_cut_v(t, cut, a, b, sc), _mono[n2 - 1])
	var u: float = t - a
	var i0: int = mini(int(u), n2 - 2)
	return lerpf(_mono[i0], _mono[i0 + 1], clampf(u - i0, 0.0, 1.0))


## 关键点曲线本体：关键点 [[秒, 池平均一下伤害], …]，首点之前取首点、末点之后取末点（封顶）；单调三次插值，处处一阶连续
static func target_raw(t: float) -> float:
	var k: Array = Bal.sec("dmg_curve").get("knots", [])
	var n: int = k.size()
	if n == 0:
		return 0.0
	if n == 1 or t <= float(k[0][0]):
		return float(k[0][1])
	if t >= float(k[n - 1][0]):
		return float(k[n - 1][1])
	var h: Array = []
	var dl: Array = []
	for i in n - 1:
		var hi: float = float(k[i + 1][0]) - float(k[i][0])
		h.append(hi)
		dl.append((float(k[i + 1][1]) - float(k[i][1])) / hi)
	var m: Array = []
	m.resize(n)
	for i in range(1, n - 1):
		if dl[i - 1] * dl[i] <= 0.0:
			m[i] = 0.0
		else:
			var w1: float = 2.0 * h[i] + h[i - 1]
			var w2: float = h[i] + 2.0 * h[i - 1]
			m[i] = (w1 + w2) / (w1 / dl[i - 1] + w2 / dl[i])
	m[0] = _end_slope(h[0], h[1] if n > 2 else h[0], dl[0], dl[1] if n > 2 else dl[0])
	m[n - 1] = _end_slope(h[n - 2], h[n - 3] if n > 2 else h[n - 2], dl[n - 2], dl[n - 3] if n > 2 else dl[n - 2])
	var j := 0
	while j < n - 2 and t >= float(k[j + 1][0]):
		j += 1
	var x: float = (t - float(k[j][0])) / h[j]
	var x2: float = x * x
	var x3: float = x2 * x
	return (2.0 * x3 - 3.0 * x2 + 1.0) * float(k[j][1]) + (x3 - 2.0 * x2 + x) * h[j] * m[j] \
		+ (-2.0 * x3 + 3.0 * x2) * float(k[j + 1][1]) + (x3 - x2) * h[j] * m[j + 1]


static func _end_slope(h0: float, h1: float, d0: float, d1: float) -> float:
	var s: float = ((2.0 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
	if signf(s) != signf(d0):
		return 0.0
	if signf(d0) != signf(d1) and absf(s) > 3.0 * absf(d0):
		return 3.0 * d0
	return s


## 威胁档刷怪池的平均基础伤害（池里重复出现的按次数加权，同刷怪抽取）
static func pool_avg(threat: int) -> float:
	if _avg.has(threat):
		return float(_avg[threat])
	var pool: Array = D.THREAT[clampi(threat, 0, D.THREAT.size() - 1)].pool
	var s := 0.0
	for id in pool:
		s += float(D.ENEMIES[id].dmg)
	var a: float = s / maxf(1.0, float(pool.size()))
	_avg[threat] = a
	return a


## 密度对单只伤害的系数 (1/density)^density_dmg_exp
static func density_k() -> float:
	var den: float = Bal.v("enemy/density", 0.4)
	return pow(1.0 / den, Bal.v("enemy/density_dmg_exp", 0.5)) if den > 0.0 else 1.0


## 时间倍率 m(t)：乘在基础伤害上（spawner.new_enemy 的 dmg_t）
static func mult(t: float, threat: int) -> float:
	if norm_full():
		var den2: float = pool_eff(threat, t) * density_k() * Bal.v("dmg_curve/ref_taken", 0.9)
		return maxf(0.05, (target_eff(t) + Bal.v("dmg_curve/ref_armor", 1.9)) / maxf(0.01, den2))
	var denom: float = pool_avg(threat) * density_k() * Bal.v("dmg_curve/ref_taken", 0.9)
	return maxf(0.05, (target(t) + Bal.v("dmg_curve/ref_armor", 1.9)) / maxf(0.01, denom))


## ---- 换档渐入 + 显式折扣（docs/335 §7，用户 11-12「让整个曲线是平缓的，或者说是渐变过渡的」）
## 旧口径：上面的 pool_avg 只按「基础伤害」归一，enemy/dmg_x_<类型>（引痕者 0.81）与威胁档 tier_dmg 乘在归一化之外，
## 换池时池平均一下跟着怪物组成跳（4:40 −16%、1:15 −2.4%、8:40 −3.8%）。
## 新口径（dmg_curve/norm_full 1）：归一化分母把 dmg_x 与渐入后的 tier_dmg 都算进去（pool_eff），池平均一下 = target_eff(t)，与组成无关；
## 原来靠 tier_dmg 压下来的平均降幅改成显式折扣 dmg_curve/relief（[秒, 系数] 折线），target_eff = 按秒累计最高的 target × relief，处处单调不降。
## tier_dmg / tier_hp 本身在换档后 enemy/tier_ramp 秒内从上一档线性过渡（tier_k），只决定同一池里高阶怪与普通怪的相对强弱。
static func norm_full() -> bool:
	return Bal.v("dmg_curve/norm_full", 0.0) > 0.0


## 威胁档 threat 在时刻 t 的分级系数（tier_hp / tier_dmg，没写按 1）：换档后 enemy/tier_ramp 秒内从上一档线性过渡；0 = 换档即跳（旧行为）
static func tier_k(key: String, t: float, threat: int) -> float:
	threat = clampi(threat, 0, D.THREAT.size() - 1)
	var cur: float = float(D.THREAT[threat].get(key, 1.0))
	var ramp: float = Bal.v("enemy/tier_ramp", 0.0)
	if threat == 0 or ramp <= 0.0:
		return cur
	var prev: float = float(D.THREAT[threat - 1].get(key, 1.0))
	return lerpf(prev, cur, clampf((t - float(D.THREAT[threat].t)) / ramp, 0.0, 1.0))


## 新口径的池平均：基础伤害 × dmg_x_<类型> × 分级系数（tier_cap 类型），按池里出现次数加权
static func pool_eff(threat: int, t: float) -> float:
	var pool: Array = D.THREAT[clampi(threat, 0, D.THREAT.size() - 1)].pool
	var tk: float = tier_k("tier_dmg", t, threat) * Bal.v("enemy/tier_dmg_scale", 1.0)
	var s := 0.0
	for id in pool:
		var ed: Dictionary = D.ENEMIES[id]
		s += float(ed.dmg) * Bal.v("enemy/dmg_x_" + str(id), 1.0) * (tk if ed.get("tier_cap", false) else 1.0)
	return s / maxf(1.0, float(pool.size()))


## 显式折扣：dmg_curve/relief 折线 [[秒, 系数], …]，首点前取首点、末点后取末点；没写 = 1
static func relief(t: float) -> float:
	var k: Array = Bal.sec("dmg_curve").get("relief", [])
	if k.is_empty():
		return 1.0
	if t <= float(k[0][0]):
		return float(k[0][1])
	for i in range(1, k.size()):
		if t <= float(k[i][0]):
			var a: float = float(k[i - 1][0])
			return lerpf(float(k[i - 1][1]), float(k[i][1]), clampf((t - a) / maxf(1e-6, float(k[i][0]) - a), 0.0, 1.0))
	return float(k[k.size() - 1][1])


static var _eff_key := []
static var _eff: PackedFloat32Array = PackedFloat32Array()   # 0..900 秒每秒累计最高的 target × relief


## 有效目标：target(t) × relief(t) 按秒取累计最高（单调保护），秒间线性插值；900 秒后取 target × relief 与 900 秒值的较大者
static func target_eff(t: float) -> float:
	var key := [Bal.sec("dmg_curve").hash(), Bal.v("growth/late_shape", 0.0), Bal.v("shape_lv/comp_from", 240.0), Bal.v("shape_lv/comp_to", 420.0), Bal.v("shape_lv/comp_dmg", 1.0)]
	if key != _eff_key:
		_eff_key = key
		_eff.resize(901)
		var m := -INF
		for i in 901:
			m = maxf(m, target(float(i)) * relief(float(i)))
			_eff[i] = m
	if t >= 900.0:
		return maxf(target(t) * relief(t), _eff[900])
	var u: float = maxf(0.0, t)
	var i0: int = mini(int(u), 899)
	return lerpf(_eff[i0], _eff[i0 + 1], clampf(u - i0, 0.0, 1.0))
