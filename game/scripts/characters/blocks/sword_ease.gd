extends RefCounted
## 剑气非线性速度（用户 10-27「做一下剑气的速度感和力量感，非线性速度」）：拉普兰德剑气 / 斯卡蒂潮刃（shape.wave 带 proj 的弹体）、
## 可见成长藏品的近战剑气（vis_growth qi）共用。爆发出手 → 快速衰减 → 末段低速滑行消散：
##   已飞比例 p(u) = (1 − glide)·(1 − (1 − u)^k) + glide·u，u = 已飞时间 / 原匀速总时长 T（T = dist / speed，不变）
##   速度倍率 p'(u) = (1 − glide)·k·(1 − u)^(k−1) + glide：出手 ≈ (1 − glide)·k + glide 倍原速，末段 glide 倍
## p(0) = 0、p(1) = 1，所以飞行总距离、存活时间与改前匀速完全相同；判定宽度 / 厚度不变，碰撞改为扫过「上一帧 → 这一帧」整段
## （出手那几帧一帧走 20+ px，不扫会穿过小怪），覆盖的路径与匀速相同，命中范围与伤害期望不变（只是命中时刻提前）。
## 旋钮 balance.json sword_ease：k / glide / stretch / bright / ghost / pause；按干员覆盖 sword_ease/ops/<干员 id>/<键>，
## 藏品剑气另按武器类取 sword_ease/styles/<类>/<键>（style 表见 vis_growth.qi_style）；积木上写 "ease": {键: 值} 再覆盖一层、"ease": 0 关掉（回到匀速）。缺省只给带 proj 的弹体式刀波；浪墙（斯卡蒂跃浪）要写 "ease": {} 才开。

const Bal = preload("res://scripts/core/balance.gd")
const KEYS := ["k", "glide", "stretch", "bright", "ghost", "pause"]
const DEF := {"k": 3.0, "glide": 0.2, "stretch": 0.35, "bright": 0.45, "ghost": 2.0, "pause": 0.025}


## 这一道刀波的曲线参数；空字典 = 匀速（总开关 sword_ease/on 为 0、积木写 "ease": 0、或浪墙没写 ease）
static func cfg(op_id: String, b: Dictionary, default_on: bool, style := "") -> Dictionary:
	if Bal.v("sword_ease/on", 1.0) <= 0.0:
		return {}
	var be = b.get("ease", null)
	if be == null and not default_on:
		return {}
	if not (be == null or be is Dictionary) and float(be) <= 0.0:
		return {}
	var c := {}
	for k in KEYS:
		var d: float = Bal.v("sword_ease/" + k, float(DEF[k]))
		if style != "":   # 按武器类（docs/170 §7）：styles/<类>/<键> 盖在全局缺省上，再被 ops/<干员> 覆盖
			d = Bal.v("sword_ease/styles/" + style + "/" + k, d)
		c[k] = Bal.v("sword_ease/ops/" + op_id + "/" + k, d)
		if be is Dictionary and be.has(k):
			c[k] = float(be[k])
	c.k = maxf(1.0, float(c.k))
	c.glide = clampf(float(c.glide), 0.0, 1.0)
	c.v0 = (1.0 - c.glide) * c.k + c.glide   # 出手速度倍率（画面「快」的上限）
	return c


## 已飞比例（0..1）
static func prog(c: Dictionary, u: float) -> float:
	if u >= 1.0:
		return 1.0
	u = maxf(u, 0.0)
	return (1.0 - c.glide) * (1.0 - pow(1.0 - u, c.k)) + c.glide * u


## 当前速度 / 原匀速
static func vel_mul(c: Dictionary, u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return (1.0 - c.glide) * c.k * pow(1.0 - u, c.k - 1.0) + c.glide


## 画面用的「快」：出手 1 → 降到原速时 0（之后的低速滑行段也是 0）
static func fast(c: Dictionary, u: float) -> float:
	if c.v0 <= 1.0001:
		return 0.0
	return clampf((vel_mul(c, u) - 1.0) / (c.v0 - 1.0), 0.0, 1.0)


## 末段压暗倍率（乘颜色，不乘透明度）：低速滑行段（速度 < 原速）从 1 渐到 0.55，读作「力尽」
static func fade(c: Dictionary, u: float) -> float:
	var vm := vel_mul(c, u)
	return 1.0 if vm >= 1.0 else lerpf(0.55, 1.0, clampf((vm - c.glide) / maxf(1.0 - c.glide, 0.001), 0.0, 1.0))


## 点到线段 [a, b] 的距离（vis_growth 圆判定的扫掠）
static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))
