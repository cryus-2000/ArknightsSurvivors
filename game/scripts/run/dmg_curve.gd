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
## mid_from 之前（前期伤害，用户亲定）不动；目标曲线仍单调（削减的斜率远小于曲线本身的斜率）。mid_cut 0 = 关
static func target(t: float) -> float:
	var cut: float = Bal.v("dmg_curve/mid_cut", 0.0)
	var v: float = target_raw(t) * Bal.v("dmg_curve/scale", 1.0)   # 全程整体倍率（难度校准 10-31，缺省 1 = 不变）
	if cut <= 0.0:
		return v
	var a: float = Bal.v("dmg_curve/mid_from", 180.0)
	var b: float = Bal.v("dmg_curve/mid_to", 420.0)
	var x: float = clampf((t - a) / maxf(1.0, b - a), 0.0, 1.0)
	return v * (1.0 - cut * x * x * (3.0 - 2.0 * x))


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
	var denom: float = pool_avg(threat) * density_k() * Bal.v("dmg_curve/ref_taken", 0.9)
	return maxf(0.05, (target(t) + Bal.v("dmg_curve/ref_armor", 1.9)) / maxf(0.01, denom))
