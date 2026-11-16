## 维什戴尔终结技「更华丽」原型（11-17 用户：想要更华丽；docs/360）。开关 ult/wd_proto（缺省 0 = 现行 V2.2 原样）：
##   位 1（=1）方向 A「蓄力锁定」：前摇 0.32 秒——炮口聚能（热芯由小到大 + 往里收的火星）、红色测距光逐排扫过落点、落点亮红锁定点（实心方块，不画细环），
##            然后一记大炮口焰 + 后坐尘 + 轻震，6 条粗弹道一起从天上砸下（取代原来的细拖线）。
##   位 2（=2）方向 B「轰炸节奏 + 终爆」：排间隔由宽到密（0.12 → 0.08），停半拍后末排落地同时在她正前方 300 处补一记大爆（只画面）：
##            爆亮冷却（大灯 0.35 秒）+ 不规整分叉裂网（热红 → 焦黑）+ 尘墙 + 隆起 + 余震；冲击帧挪到这一下；弹坑留更久、冒余烬。
##   =3 两个叠加。判定点 / 伤害比例不动；A 让全部落点晚 0.32 秒，B 改排间隔（总长仍 ≤ 1.2 秒）。
## 低画质（Cfg.quality == "low"）：不画尘墙、裂网减半、不放余烬和聚能火星，炮口 / 终爆只留帧条和一盏灯。纯画面 + 两声 cue，不碰随机数
const PF = preload("res://scripts/run/ult_pixfx.gd")
const Bal = preload("res://scripts/core/balance.gd")

const CHARGE := 0.32   # A：前摇加长（秒）
const B_OFFS := [0.0, 0.12, 0.23, 0.32, 0.40, 0.60]   # B：6 排落地时刻（相对第一排）；末排前停半拍
const RED := Color("#c41e18")
const HOT := Color("#ffa868")
const SPARK := Color("#f04a24")
const CHAR := Color(0.16, 0.05, 0.05)
const FORKS := ["fx_ul_crack_fork", "fx_ul_crack_fork2", "fx_ul_crack_fork3", "fx_ul_crack_fork4"]


static func mode() -> int:
	return int(Bal.v("ult/wd_proto", 0.0))


static func a_on() -> bool:
	return mode() & 1 != 0


static func b_on() -> bool:
	return mode() & 2 != 0


static func low() -> bool:
	return Cfg.quality == "low"


## 第 k 排落地时刻
static func row_t(k: int, t0: float, gap: float) -> float:
	if b_on() and k < B_OFFS.size():
		return t0 + float(B_OFFS[k])
	return t0 + gap * float(k)


## A：聚能 + 锁定 + 开炮（_wd_start 里调；t_fire = 开炮时刻，第一排落地前 0.1 秒）
static func charge_lock(u, o, d: Vector2, shells: Array, t_fire: float) -> void:
	var mz: Vector2 = o.pos + d * 40.0 + Vector2(0, -20)
	# 聚能：三层实心热芯依次长大（暗红 → 红 → 橙白），开炮时熄
	var cores := [[RED, 40.0, 0.0], [SPARK, 27.0, 0.08], [HOT, 14.0, 0.16]]
	for c in cores:
		var dl: float = float(c[2])
		u.shape({"kind": "circle", "c": mz, "r": float(c[1]), "col": c[0], "fill": 0.95, "life": t_fire - dl, "delay": dl})
	u.light(mz, 140.0, SPARK, t_fire)
	if not low():   # 往炮口收的火星（从外圈飞向炮口）
		for i in 10:
			var hq: float = PF.h(float(i) * 3.7 + mz.x * 0.01)
			var dv := Vector2.from_angle(TAU * (float(i) + hq) / 10.0)
			var r0: float = 70.0 + 40.0 * hq
			var lf: float = 0.16 + 0.06 * hq
			u.shape({"kind": "dots", "c": mz + dv * r0, "r": 6.0, "n": 2, "col": HOT, "life": lf, "delay": 0.02 * float(i % 5), "v": -dv * r0 / lf})
	# 测距光：从炮口逐排扫到每排中心（一条红光扫一下），每个落点留一枚实心锁定方块，闪两下到落地
	for k in shells.size():
		var sh: Dictionary = shells[k]
		var row: Array = sh.ps
		var mid: Vector2 = row[1]
		var dk: float = 0.03 + 0.035 * float(k)
		u.shape({"kind": "blade", "a": mz, "b": mid, "w": 7.0, "col": Color(1.0, 0.55, 0.45), "glow": RED, "grow": 0.04, "life": 0.16, "fo": 0.05, "delay": dk})
		for p in row:   # 每个锁定点按落点哈希转个角、大小 0.75–1.25、出现错开 0–0.06 秒（预审报同形等距排列）
			var hq: float = PF.h(p.x * 0.017 + p.y * 0.031)
			var dl2: float = dk + 0.05 + 0.06 * hq
			var lt: float = float(sh.t) - dl2
			var sz: float = 0.75 + 0.5 * PF.h(hq * 13.0)
			var ax := Vector2.from_angle((hq - 0.5) * 0.7) * 36.0 * sz
			u.shape({"kind": "rock", "c": p, "r": 17.0 * sz, "col": RED, "glow": HOT, "seed": hq * 50.0, "rot": hq * TAU, "fill": 0.95, "life": lt, "delay": dl2})
			u.shape({"kind": "line", "a": p - ax, "b": p + ax, "w": 6.0, "col": RED, "life": lt, "delay": dl2})
			u.shape({"kind": "line", "a": p - ax.orthogonal(), "b": p + ax.orthogonal(), "w": 6.0, "col": RED, "life": lt, "delay": dl2})
	# 开炮：大炮口焰 + 后坐尘 + 轻震（cue fire 由原有 fx_cannon_burst 帧条配声；这里只补画面）
	var cb: String = "fx_cannon_burst_br" if u.fx_ready("fx_cannon_burst_br") else "fx_cannon_burst"
	u.strip(cb, mz + d * 30.0, {"sc": 3.2, "ang": d.angle(), "delay": t_fire})
	u.shape({"kind": "blade", "a": mz, "b": mz + d * 220.0, "w": 22.0, "col": Color(1.0, 0.85, 0.7), "glow": SPARK, "grow": 0.03, "life": 0.12, "fo": 0.07, "delay": t_fire})
	u.light(mz + d * 60.0, 260.0, HOT, 0.25)
	if not low():
		PF.dust(u, o.pos - d * 50.0, 170.0, t_fire, mz.x * 0.03, -d * 90.0, Color(0.9, 0.7, 0.66))
	# 天降弹道：每排一条粗弹道，比落地早 0.12 秒从右上斜砸下（头亮尾红）
	for k in shells.size():
		var sh: Dictionary = shells[k]
		var mid: Vector2 = sh.ps[1]
		var ts: float = float(sh.t)
		for p in sh.ps:
			var top: Vector2 = p + Vector2(-140, -620)
			u.shape({"kind": "blade", "a": top, "b": top + (p - top) * 0.35, "w": 9.0, "col": Color(1.0, 0.9, 0.75), "glow": SPARK, "life": 0.12, "fo": 0.03,
				"delay": ts - 0.12, "v": (p - top) * 0.65 / 0.12})


## A：开炮瞬间的一下震（_wd_step 每帧调，到点放一次）
static func fire_tick(u, a: Dictionary, t: float) -> void:
	if a.has("fire_t") and not a.get("fired", false) and t >= float(a.fire_t):
		a["fired"] = true
		u.shake(4.0, 0.12)
		u.cue("salvo")


## B：最后一排合成终爆（主爆帧条之外的东西：大灯冷却、裂网、尘墙、隆起、余震、大粒子）
static func finale(u, a: Dictionary, shells: Array, rr: float, vs: float) -> void:
	# 落在她正前方 300 处（炮击带长约 1000、末排常在屏外；手机竖屏视野更短）。终爆只是画面，判定仍是末排三发
	var c: Vector2 = a.o0 + a.d * Bal.v("ult/wd_fin_d", 300.0)
	var cn: String = "fx_wd_cannon_br" if u.fx_ready("fx_wd_cannon_br") else ("fx_wd_cannon" if u.fx_ready("fx_wd_cannon") else "fx_wisadel_cannon")
	u.strip(cn, c, {"sc": 4.4, "ang": (PF.h(vs) - 0.5) * 0.6, "hf": true})
	u.light(c, rr * 3.6, HOT, 0.35)   # 爆亮冷却：一盏大灯 0.35 秒灭
	u.shake(5.0, 0.2)
	u.cue("finale")
	var n_cr: int = 5 if low() else 10
	PF.crack_net(u, FORKS, c, rr * 2.6, n_cr, PF.h(vs + 1.0) * TAU, vs, 0.16, Color(1.15, 0.45, 0.32), CHAR, rr * 0.45, true)
	if low():
		return
	PF.particles(u, c, 300, "ult_burst", [SPARK, RED], 0.03, vs + 5.0, rr * 2.1)
	PF.wall(u, c, rr * 1.3, 0.05, Color(0.95, 0.7, 0.66, 0.85))
	PF.heave(u, c, rr * 1.5, vs + 3.0, 0.04, Color(0.9, 0.78, 0.76), 95.0)
	PF.aftershock(u, c, rr * 1.4, vs + 7.0, 0.3, 10, Color(0.9, 0.78, 0.76))
	PF.dust(u, c + Vector2(-rr * 0.6, -10), 260.0, 0.1, vs * 3.0, Vector2(-40, -10), Color(0.95, 0.72, 0.68))
	PF.dust(u, c + Vector2(rr * 0.6, 10), 230.0, 0.16, vs * 5.0, Vector2(40, 10), Color(0.95, 0.72, 0.68))


## B：每发炮弹的余烬（弹坑上冒一小团慢火星；约三分之一炮弹，预审报一格格重复）
static func ember(u, p: Vector2, rk: float, delay: float, hp: float) -> void:
	if low() or hp > 0.33:
		return
	PF.particles(u, p, 60, "ult_ember", [SPARK, HOT], delay + 0.25, hp * 91.0, 70.0 * rk)


## 出招时先把终爆 / 余烬要用的贴图读进缓存（第一次用时现读会卡一帧：11-17 实测终爆那帧最大帧时 76 → 106 ms）
static func warm(u) -> void:
	if not b_on():
		return
	for nm in FORKS + [PF.WALL, "fx_px_burst1", "fx_px_burst2", "fx_px_burst_s", "fx_dust_seq"]:
		u.fx_ready(nm)
