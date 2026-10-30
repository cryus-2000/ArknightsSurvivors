extends RefCounted
## 特效与提示：帧条特效（V6_FRAMES 的 fx_*）、旧式整条动画、刀光 / 爪痕、火花、飘字、横幅、屏幕震动；
## 加色混合层（fx_add 节点）的绘制；特效与各种提示计时的逐帧衰减。干员经 characters/op_api.gd 调用。2026-09-26 从 game.gd 拆出。

const A = preload("res://scripts/art.gd")
const UI = preload("res://scripts/ui.gd")
const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")
const Look = preload("res://scripts/render/look.gd")
const Dc = preload("res://scripts/render/declutter.gd")   # 后期降噪预设（render/declutter）
const UM = preload("res://scripts/ui_motion.gd")
const FD = preload("res://scripts/render/frame_dst.gd")   # 精灵取帧 + 落点（docs/101 B4 ②）
const BossBeam = preload("res://scripts/render/boss_beam.gd")   # Boss 颗粒层是否开着（grains）：开着时绿色水花 / 邪能贴图让位给专属色颗粒

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
## 斩击 / 爪痕帧的统一缩放（2026-09-25）：帧条本身只有 28–56 像素，各干员按「命中半径 ÷ 帧宽」放大后
## 常到 4–6 倍，像素颗粒比人物（PX = 2 倍）粗一倍多，又大又糙。统一 ×0.7 再封顶 3 倍：弧光比判定略小，
## 判定范围由地面环 / 裂纹表达。_fx_sprite（fx_slash_* / fx_claw_*）与 _slash_fx 都走这里
const BLADE_SCALE_K := 0.7
const BLADE_SCALE_MAX := 3.0
const FX_SCALE_MAX := 3.2        # 所有帧条特效（碎石 / 水花 / 法阵…）的放大上限，避免颗粒比人物粗太多
## 受击材质：甲壳 / 灵体，其余为血肉
const HIT_SHELL := ["stone", "spitter", "pocket", "mimic", "path", "fractal", "iberia", "carmen"]
const HIT_SPIRIT := ["skimmer", "paranoia", "tear", "brood", "bishop", "ishar"]


## Local contact feedback; no camera shake and no gameplay RNG.
var contact_at := {}
var impact_at := -99.0


## Shared stop budget: at most once per 0.28 simulation seconds, never cumulative.
## An explicit heavy impact may upgrade the small contact on the same frame.
## 另受真实时间最小间隔约束（stop，docs/50 §10）
func impact_pause(seconds: float) -> void:
	if g.t < impact_at:
		impact_at = -99.0
	if g.t - impact_at < 0.28 and absf(g.t - impact_at) > 0.0001:
		return
	if not stop(clampf(seconds, 0.0, 0.075), "impact"):
		return
	impact_at = g.t


## 顿帧总闸（docs/50 §10，后期卡顿；用户 10-11：顿帧手感保留）：所有 g.hitstop 都从这里走。每次顿帧的时长不变，
## 只加一条按**真实时间**算的最小间隔 fx/hitstop_gap（秒）：上一次顿帧开始后不到这么久的触发直接丢掉、不排队。
## 原来只有 impact_pause 有「0.28 模拟秒一次」的限频，模拟秒在顿帧期间不走，主控受击 / 精英击杀又不受限，后期几乎每 0.3 秒
## 顿一次（命中、暴击 / 大体型击杀、重型干员接触），连成一片读作卡顿；一片小怪同时倒下也只顿一次（同一间隔内）。
## must（生命垂危、精英 / Boss 击杀）不受间隔限制，但同样记为「上一次顿帧」。
## 纯画面节奏：平衡 / 批跑不消耗 g.hitstop（game.gd 只在玩家局与 --playclock 里走顿帧），不碰随机数，TRACE / BALANCE 不变
var _stop_ms := -1000.0
var _stop_frame := -1
var stop_stat := {}   # kind -> [请求, 实给, 实给秒数]（--perf 打印）


func stop(seconds: float, kind: String, must := false) -> bool:
	var st: Array = stop_stat.get(kind, [0, 0, 0.0])
	stop_stat[kind] = st
	st[0] += 1
	var add: float = seconds - maxf(0.0, g.hitstop)
	if add <= 0.0:
		return true
	var now := UM.now()   # 界面时钟：累计真实帧间隔（顿帧期间照走；--fixed-fps 录片时按固定步长，节奏与真机一致）
	var fr := Engine.get_process_frames()
	# 同一帧里后来的更重的一下可以把刚给的顿帧加长（同 impact_pause 原来的「同帧升级」）
	if not must and not g.perf_alt and fr != _stop_frame and now - _stop_ms < Bal.v("fx/hitstop_gap", 0.5):
		return false   # g.perf_alt：--perfab 同局对照时的旧规则（没有真实时间间隔）
	_stop_ms = now
	_stop_frame = fr
	g.hitstop = seconds
	st[1] += 1
	st[2] += add
	return true


var _feel := {}


## 干员的打击手感类别（json hit_feel：heavy / melee / 空），按 id 缓存
func hit_feel(oid: String) -> String:
	var f = _feel.get(oid)
	if f == null:
		var o = g.squad.get_op(oid) if g.squad != null else null
		f = str(o.def.get("hit_feel", "")) if o != null else ""
		_feel[oid] = f
	return f


func contact(oid: String, e: Dictionary, origin: Vector2, source := "") -> void:
	var prev: float = contact_at.get(oid, -99.0)
	if g.t >= prev and g.t - prev < 0.18:
		return
	contact_at[oid] = g.t
	if (e.pos as Vector2).distance_to(g.ppos) > 650.0:
		return
	var feel: String = hit_feel(oid)   # hit_feel：干员 json（heavy 重击 / melee 近战）
	var heavy: bool = feel == "heavy"
	var melee: bool = feel == "melee"
	var color := Color(0.72, 0.84, 0.92) if heavy or melee else Color(0.55, 0.65, 0.92)
	var direction: Vector2 = (e.pos - origin).normalized()
	# 普通命中火花：用户 10-14 定去掉（受击白闪 + 伤害数字 + 击退已够；满屏淡紫小点和弱点火花混淆）。fx/contact_sparks 1 = 恢复
	if Bal.vi("fx/contact_sparks", 0) > 0:
		sparks(e.pos + Vector2(0, -e.r * 0.6), direction, color, 3 if heavy else 2, 120.0 if heavy else 75.0)
	# Continuous fields and secondary damage retain sparks without a global pause.
	if source in ["替身", "血色潮痕", "余震", "殉爆", "钙晶", "碎晶", "急救针剂", "技能·法术", "触手"]:
		return
	# Continuous magic and healing never interrupt control with global hitstop.
	if heavy:
		impact_pause(0.032)
	elif melee:
		impact_pause(0.018)


## 命中反馈分档（打击感审查，协调人 9/30）：combat.damage 每次命中调用，只改画面（白闪 e.flash、受击形变 e.squash、
## 粒子、破绽时的短顿帧），不碰模拟随机数（粒子用 g.vrng）。参数都在 data/balance.json 的 fx 段：
## - 持续伤害（dot 标签）：白闪 / 形变减弱，免得持续伤害让敌人一直闪白
## - 普攻：原来的 0.08 / 0.14
## - 技能（origin == skill）：白闪更长、形变更久
## - 暴击：金色小火花；弱点：按弱点类型着色的小火花
## - 破绽中的 Boss：白闪最长 + 金色火花 + 金色冲击环 + 短顿帧（每只 Boss 每 fx/break_every 秒最多一次，顿帧再受 impact_pause 的共享限频）
const WEAK_SPARK := {"物理": Color(1.0, 0.75, 0.3), "法术": Color(0.7, 0.55, 1.0)}
var _break_fx_at := {}

## 特效第 2 步（10-23 用户定）：普攻命中统一「轻 / 中 / 重」三档模板（10-29 起常开，旧开关 fx/hit_tiers 已删）。
## 分档：单发伤害相对该干员普攻基准（按干员滑动平均，暴击 / 弱点不进基准）< fx/hit_mid（1.2）倍轻、< fx/hit_heavy（2.5）倍中、
## 以上或暴击 / 弱点重；召唤物、追加打击（follow_up / aftershock）一律轻。只认带 basic 标签的普攻与召唤物，技能 / 持续伤害照旧。
## 每档：迸溅颗粒 fx/hit_n（3 / 6 / 12，干员本色）、白闪时长、命中闪光大小与亮度、顿帧（轻 0 / 中 fx/hit_pause_m / 重 fx/hit_pause_h，
## 走 impact_pause 的共享限频）、命中音（三档音量 / 音高，Sfx 自带限流）。纯画面：粒子用 g.vrng / GPU，不碰模拟随机数，TRACE 不变
var _hit_base := {}   # 干员 id → 普攻单发伤害基准
var tier_off := false   # --tierab 同局轮换（只供性能对照）：true = 这一段不分档、不画刀光
var _tier_force := -2   # --hittier=N 截图对照：普攻一律按第 N 档；-1 = 不强制（-2 = 还没读参数）
var _open_arcs := {}    # 干员 id → 这一帧刚画的刀光（同帧命中按三档更新它的粗细亮度）
var arc_dbg := -1       # --arcdbg：刀光旁边再画判定圈与扇形边（核对用）


## 近战刀光（character.arc_targets 调）：同一干员同一模拟时刻同一判定只画一道；粗细亮度先按轻档，命中后由 hit_react 升档
func melee_arc(o, origin: Vector2, ang: float, half: float, radius: float) -> void:
	if tier_off or g.fx.size() > 420:
		return
	var key: String = str(o.id)
	var prev = _open_arcs.get(key)
	if prev != null and float(prev.t) == g.t and (prev.org as Vector2).distance_to(origin) < 1.0 and absf(float(prev.r) - radius) < 0.5 and absf(float(prev.half) - half) < 0.01 and absf(angle_difference(float(prev.ang), ang)) < 0.01:
		return
	var c: Color = o.col()
	var mx: float = maxf(c.r, maxf(c.g, c.b))
	if mx > 1.0:
		c = Color(c.r / mx, c.g / mx, c.b / mx)
	# 跟着挥刀走（10-24 用户「近战刀光跟着挥刀的动作走」）：时长 = 这名干员出手帧之后剩余动作的六成（夹在 fx/melee_arc_life 与 0.22 秒之间），
	# 刀光从挥刀起点一侧扫到另一侧；起点取屏幕上更高的那一端（自上而下劈），全圆（旋身斩）按朝向转一圈
	var life: float = clampf((float(o.attack_dur) - float(o.attack_fire_at)) * 0.6, Bal.v("fx/melee_arc_life", 0.12), 0.22)
	var sdir := 1.0
	if half >= PI - 0.01:
		sdir = 1.0 if float(o.face) >= 0.0 else -1.0
	elif sin(ang + half) < sin(ang - half):
		sdir = -1.0   # +half 那一端更高：从 +half 扫向 −half
	if arc_dbg < 0:
		arc_dbg = 1 if Cfg.dev_args().has("--arcdbg") else 0
	if arc_dbg == 1:
		life *= 5.0   # 核对截图：刀光多留一会儿，和判定圈叠在一起好看清
	# off：判定原点相对干员脚底的偏移，绘制时按干员当前位置算（移动攻击时刀光跟着人走）；org 只用于同帧去重
	if half >= PI - 0.01:
		ang = 0.0 if float(o.face) >= 0.0 else PI   # 360° 判定没命中时朝面向画（命中后改朝被打中的敌人）
	var f := {"kind": "marc", "pos": origin, "org": origin, "op": key, "off": origin - (o.pos as Vector2), "sdir": sdir,
		"ang": ang, "half": half, "r": radius, "col": c, "tier": 1, "life": life, "max": life, "t": g.t}
	g.fx.append(f)
	_open_arcs[key] = f


## ① 光学新击杀：刚加进 g.fx 的死亡帧条按帧等比加快（普通 ≤ fx/death_max、精英 ≤ fx/death_max_elite、Boss 不变），
## 并挂上「播完那一刻按最后一帧碎成像素碎屑」（vfx.update → _shatter → optical_particles.kill_burst_frame）。返回是否挂上
func death_shatter(e: Dictionary, name: String, origin: Vector2, sc: float, anchor: Vector2) -> bool:
	if g.fx.is_empty() or g.fx[-1].get("name", "") != name:
		return false
	var f: Dictionary = g.fx[-1]
	var spec: Array = Game.V6_FRAMES[name]
	var cap: float = 99.0 if e.get("boss", false) else (Bal.v("fx/death_max_elite", 0.5) if e.get("elite", false) else Bal.v("fx/death_max", 0.3))
	var k: float = maxf(1.0, float(f.max) / maxf(0.05, cap))
	f.fps = float(spec[1]) * k
	f.max = float(f.max) / k
	f.life = f.max
	f.shatter = {"e": e, "origin": origin, "sc": sc, "anchor": anchor, "frame": int(spec[0]) - 1, "flip": f.get("flip", false)}
	return true


func _shatter(f: Dictionary) -> void:
	var s: Dictionary = f.shatter
	f.erase("shatter")
	if g.optical_on and g.optical.particles != null:
		g.optical.particles.kill_burst_frame(s.e, f.name, s.frame, s.origin, s.sc, s.anchor, s.flip)


## ② 开火微震（用户 10-24）：只给队长自己的普攻按命中档轻 0 / 中 fx/kick_px2 / 重 fx/kick_px3 美术像素，fx/kick_t 秒内阶梯回位；
## 写 world.leader_kick（只进 cam.offset，不动 cam.position、不进模拟）；同一帧多段命中取最大档；「减少动态效果」开时不震
func _leader_kick(h: Dictionary, e: Dictionary, tier: int) -> void:
	if tier < 2 or Cfg.reduce_motion or Bal.v("fx/leader_kick", 1.0) <= 0.0 or g.ch == null or str(h.get("op", "")) != str(g.ch.id):
		return
	var px: int = Bal.vi("fx/kick_px3", 2) if tier == 3 else Bal.vi("fx/kick_px2", 1)
	g.world.kick(((e.pos as Vector2) - g.ppos), px, Bal.v("fx/kick_t", 0.06))


## ── 突出队长（docs/139 §11，用户 10-25「队友特效不要降，想其它办法」）──
## render/lead_hitmark 1：队长打中的敌人身上出四个像素角标（暖白，0.3 秒，同一只敌人重复命中只刷新寿命，不叠、不闪）；队友 / 召唤物命中没有
## lead_hit_dir / lead_hit_t：队长最近一次命中方向（squad.draw_leader_mark 的朝向弧用，render/lead_dir）
var lead_hit_dir := Vector2.ZERO
var lead_hit_t := -10.0
func lead_mark(e: Dictionary) -> void:
	lead_hit_dir = ((e.pos as Vector2) - g.ppos).normalized()
	lead_hit_t = g.t
	if (Bal.vi("render/lead_hitmark", 0) <= 0 and g.world.lead_lv <= 0) or g.fx.size() > 400:
		return
	var f = e.get("_lead_mk")
	if f is Dictionary and float(f.life) > 0.0:
		f.life = f.max
		return
	var nf := {"kind": "lead_mark", "pos": e.pos, "e": e, "r": float(e.get("r", 12.0)), "life": 0.3, "max": 0.3}
	e["_lead_mk"] = nf
	g.fx.append(nf)


func is_lead_hit(h: Dictionary) -> bool:
	return g.ch != null and str(h.get("op", "")) == str(g.ch.id) and h.get("emitter", "") != "summon"   # 召唤物的命中不算队长本人出手


func hit_tier(h: Dictionary, dmg: float, crit: bool, weak: bool) -> int:
	if tier_off:
		return 0
	if _tier_force == -2:
		_tier_force = -1
		for a in Cfg.dev_args():
			if a.begins_with("--hittier="):
				_tier_force = clampi(int(a.substr(10)), 1, 3)
	var tags: Array = h.get("tags", [])
	if "dot" in tags:
		return 0
	var summon: bool = h.get("emitter", "") == "summon"
	if not summon and not ("basic" in tags):
		return 0
	if _tier_force > 0:
		return _tier_force
	if summon or "follow_up" in tags or "aftershock" in tags:
		return 1
	var key: String = str(h.get("op", "")) if str(h.get("op", "")) != "" else str(h.get("src", ""))
	var base: float = float(_hit_base.get(key, dmg))
	if not (crit or weak):
		_hit_base[key] = lerpf(base, dmg, 0.08)
	var ratio: float = dmg / maxf(base, 0.001)
	if crit or weak or ratio >= Bal.v("fx/hit_heavy", 2.5):
		return 3
	if ratio >= Bal.v("fx/hit_mid", 1.2):
		return 2
	return 1


func _op_col(h: Dictionary) -> Color:
	var o = g.squad.get_op(str(h.get("op", ""))) if g.squad != null and str(h.get("op", "")) != "" else null
	var c: Color = o.col() if o != null else Color(0.8, 0.95, 1.0)
	var mx: float = maxf(c.r, maxf(c.g, c.b))
	return Color(c.r / mx, c.g / mx, c.b / mx) if mx > 1.0 else c


## Boss 受击白闪限频（docs/137，10-24）：两次白闪的起点至少隔 fx/boss_flash_gap 秒（缺省 0.4 → 每秒最多 2.5 次，低于光敏安全的 3 次），
## 每次持续 fx/boss_flash_t 秒、线性淡出；间隔内的命中不续时、不重启。持续伤害不闪。原来每一下命中都续白闪，多人围打时 Boss 每秒闪 6–7 次、
## 六七成时间是白的。只管画面：e.flash 只有绘制在读，boss_flash_at 记的是 g.t
static func boss_hit_flash(e: Dictionary, now: float, dot := false) -> void:
	if dot:
		return
	var last: float = e.get("boss_flash_at", -1000.0)
	if now >= last and now - last < Bal.v("fx/boss_flash_gap", 0.4):
		return
	e.boss_flash_at = now
	e.flash = Bal.v("fx/boss_flash_t", 0.09)


## Boss 白闪当前透明度：峰值 peak 随剩余时间线性淡出
static func boss_flash_alpha(e: Dictionary, peak: float) -> float:
	return peak * clampf(float(e.get("flash", 0.0)) / maxf(0.001, Bal.v("fx/boss_flash_t", 0.09)), 0.0, 1.0)


func hit_react(e: Dictionary, crit: bool, weak: bool, hd: Dictionary = {}, dmg := 0.0) -> void:
	var h: Dictionary = hd if not hd.is_empty() else g.hit   # combat.damage 显式传这一下的描述符（docs/101 B7 ⑤）
	var dot: bool = "dot" in h.get("tags", [])
	var skill: bool = h.get("origin", "") == "skill" and not dot
	var brk: bool = e.get("boss", false) and float(e.get("break_t", 0.0)) > 0.0
	var fl: float = Bal.v("fx/flash_dot", 0.05) if dot else Bal.v("fx/flash_basic", 0.08)
	var sq: float = Bal.v("fx/squash_dot", 0.08) if dot else Bal.v("fx/squash_basic", 0.14)
	if skill:
		fl = maxf(fl, Bal.v("fx/flash_skill", 0.11))
		sq = maxf(sq, Bal.v("fx/squash_skill", 0.18))
	if crit or weak:
		fl = maxf(fl, Bal.v("fx/flash_crit", 0.12))
		sq = maxf(sq, Bal.v("fx/squash_skill", 0.18))
	if brk and not dot:
		fl = maxf(fl, Bal.v("fx/flash_break", 0.14))
	var tier: int = hit_tier(h, dmg, crit, weak)
	if tier > 0:
		fl = maxf(fl, [0.0, 0.06, 0.09, 0.13][tier])
	if e.get("boss", false):
		boss_hit_flash(e, g.t, dot)   # Boss 白闪限频（docs/137）；普通怪 / 精英照旧
	else:
		e.flash = maxf(float(e.get("flash", 0.0)), fl)
	# Boss 受击不压扁（用户 10-29「boss 受到攻击不变瘪」，docs/201）：中期 / 最终 Boss 各形态只留限频白闪；fx/boss_squash > 0 时按比例压，且两次至少隔 0.6 秒
	if e.get("boss", false):
		var bk: float = Bal.v("fx/boss_squash", 0.0)
		if bk > 0.0 and g.t - float(e.get("bsq_at", -99.0)) >= 0.6:
			e.bsq_at = g.t
			e.squash = maxf(float(e.get("squash", 0.0)), sq * bk)
	else:
		e.squash = maxf(float(e.get("squash", 0.0)), sq)
	if not dot and is_lead_hit(h):
		lead_mark(e)
	if tier > 0:
		_tier_fx(e, h, tier)
		_leader_kick(h, e, tier)
		var arc = _open_arcs.get(str(h.get("op", "")))
		if arc != null and float(arc.t) == g.t:
			arc.tier = maxi(int(arc.tier), tier)   # 同一挥砍里打出的最高档决定刀光粗细亮度
			if float(arc.half) * 2.0 > deg_to_rad(Bal.v("fx/melee_arc_span", 105.0)) and not arc.get("aimed", false):
				arc.ang = ((e.pos as Vector2) - (arc.org as Vector2)).angle()   # 宽扇形 / 360°：月牙只画在第一个被打中的敌人那一侧
				arc.aimed = true
	elif g.optical_on and g.optical.particles != null and not dot:
		g.optical.particles.hit_spark(e.pos + Vector2(0, -e.r * 0.6), Color(1.0, 0.95, 0.85) if not (crit or weak) else Color(1.0, 0.8, 0.35))   # 光学观感原型：命中迸溅（限频，纯画面）
	# 受击后坐（docs/53，纯画面）：本体沿「远离主控」的方向顶开 fx/recoil_px，fx/recoil_t 秒内回位；技能 / 暴击 / 弱点 ×fx/recoil_skill_k。
	# 只写 rc_at / rc_dir / rc_k 三个字段，位移在 render/world.gd 的 _eoff 里按 g.t 算（缓存路径和原路径同一个表达式，不进签名）。
	# 持续伤害不顶；Boss 不顶（韧性的观感，Boss 的受击反馈走破绽）
	# Boss 受击抖动（10-28 用户「boss霸体时候挨打没有受击动画」）：Boss 不做后坐，原来的受击反馈靠击退把本体顶起一点（data.enemy_offset 按 kb），
	# 霸体不吃击退后就只剩限频白闪。所有 Boss 命中时画面抖一下：沿远离队长方向顶出再回位（fx/boss_shake_px 世界像素、fx/boss_shake_t 秒），
	# 抖动中的再次命中不重启（不嗡嗡响）。只挪画面，不碰位置 / 击退；Boss 不走普通怪缓存画法，不涉及 _dc_ok
	# 10-29（docs/201）：试炼里没有杂兵分火，每秒约 10 下命中，原来只隔 0.1 秒就能再抖，Boss 三四成时间都在抖、看着一直在受击；
	# 两次抖动起点至少隔 fx/boss_shake_gap 秒、幅度 fx/boss_shake_px 降到 2.5
	if not dot and e.get("boss", false) and g.t - float(e.get("bh_at", -99.0)) >= maxf(Bal.v("fx/boss_shake_t", 0.1), Bal.v("fx/boss_shake_gap", 0.6)):
		var bd: Vector2 = (e.pos as Vector2) - g.ppos
		e.bh_dir = bd.normalized() if bd.length_squared() > 1.0 else Vector2.RIGHT
		e.bh_at = g.t
		e.bh_px = Bal.v("fx/boss_shake_px", 2.5) *(1.5 if (skill or crit or weak or tier >= 2) else 1.0)
		e.bh_t = Bal.v("fx/boss_shake_t", 0.1)
	if not dot and not e.get("boss", false):
		var d: Vector2 = (e.pos as Vector2) - g.ppos
		e.rc_dir = d.normalized() if d.length_squared() > 1.0 else Vector2(1.0, 0.0)
		e.rc_at = g.t
		e.rc_k = Bal.v("fx/recoil_skill_k", 1.6) if (skill or crit or weak) else 1.0
		# ③ 分档后坐（用户 10-24）：三档普攻按 轻 fx/recoil_px1 / 中 fx/recoil_px2 / 重 fx/recoil_px3 美术像素顶开、fx/recoil_tier_t 秒回弹（只挪画面）
		if tier > 0:
			var tpx: float = [0.0, Bal.v("fx/recoil_px1", 2.0), Bal.v("fx/recoil_px2", 3.0), Bal.v("fx/recoil_px3", 5.0)][tier]
			e.rc_k = tpx * Game.PX / maxf(0.01, g.world.rc_px)
			e.rc_t = Bal.v("fx/recoil_tier_t", 0.08)
		else:
			e.erase("rc_t")
		# 重击真实击退（开关 fx/heavy_knockback，缺省 0 = 关；开了会改玩法）：重档普攻沿远离队长方向加击退速度
		if tier == 3 and Bal.v("fx/heavy_knockback", 0.0) > 0.0 and not e.get("elite", false):
			g.enemies_sys.apply_kb(e, e.rc_dir * Bal.v("fx/heavy_knockback", 0.0))   # 统一入口（cc_lint）：含失重倍率
	if (e.pos as Vector2).distance_to(g.ppos) > 700.0 or g.fx.size() > 380:
		return
	var head: Vector2 = e.pos + Vector2(0, -float(e.get("r", 12.0)) * 0.6)
	if crit:
		sparks(head, Vector2.ZERO, UI.GOLD, Bal.vi("fx/crit_sparks", 4), 170.0)
	elif weak and not dot:
		sparks(head, Vector2.ZERO, WEAK_SPARK.get(e.get("weak", ""), Color(1.0, 0.5, 0.8)), Bal.vi("fx/weak_sparks", 3), 130.0)
	if brk and not dot:
		var key: int = int(e.get("id", 0))
		var prev: float = _break_fx_at.get(key, -99.0)
		if g.t >= prev and g.t - prev < Bal.v("fx/break_every", 0.15):
			return
		_break_fx_at[key] = g.t
		sparks(head, Vector2.ZERO, UI.GOLD, Bal.vi("fx/break_sparks", 6), 240.0)
		g.fx.append({"kind": "ring", "pos": head, "r": float(e.get("r", 20.0)) * 0.9 + 14.0, "life": 0.22, "max": 0.22, "col": Color(1.6, 1.25, 0.45), "op_hit": true})
		impact_pause(Bal.v("fx/break_pause", 0.035))


## 三档命中的画面 / 声音（hit_tier 定档后调；远处 / 特效过多时只留白闪）
func _tier_fx(e: Dictionary, h: Dictionary, tier: int) -> void:
	if tier >= 2:
		impact_pause(Bal.v("fx/hit_pause_h", 0.03) if tier == 3 else Bal.v("fx/hit_pause_m", 0.014))
	Sfx.play("hit", [0.0, -17.0, -12.0, -8.0][tier], [1.0, 1.25, 1.05, 0.85][tier])
	if (e.pos as Vector2).distance_to(g.ppos) > 700.0 or g.fx.size() > 380:
		return
	var col: Color = _op_col(h)
	var head: Vector2 = e.pos + Vector2(0, -float(e.get("r", 12.0)) * 0.6)
	var n: int = [0, Bal.vi("fx/hit_n1", 3), Bal.vi("fx/hit_n2", 6), Bal.vi("fx/hit_n3", 12)][tier]
	var lead: bool = g.ch != null and str(h.get("op", "")) == str(g.ch.id)
	if lead and g.world.lead_lv > 0:
		col = g.world.lead_col(col)   # 队长命中颗粒 / 命中星：提亮 / 暖色（docs/139 §11）
	if not lead and g.world.mate_on:
		col = g.world.mate_col(col)   # 队友命中颗粒：去饱和、压透明度（docs/139 §10；敌人身上的白闪不动）
		col.a = g.world.mate_dim

	if (g.optical_on or Cfg.quality == "low") and g.optical.grains != null and g.optical.grains.on() and not g.optical.grains.off:   # 低档也走颗粒火星（按 low_grains 少量，docs/50 §36）
		g.optical.grains.spark(head, (e.pos as Vector2).y + float(e.get("r", 12.0)) * 0.8, col, n)   # 刀光第四版：带重力、落到脚底高度停住冷却的火星（docs/136）
	elif g.optical_on and g.optical.particles != null:
		g.optical.particles.tier_burst(head, col, tier)   # GPU 颗粒（池化、局部预算、中画质减半）
	else:
		sparks(head, Vector2.ZERO, col, n, [0.0, 90.0, 140.0, 200.0][tier])
	if tier >= 2:
		var k: float = 1.3 if tier == 2 else 1.7
		glow(head, [0.0, 6.0, 10.0, 16.0][tier], Color(col.r * k, col.g * k, col.b * k, 0.8 * col.a), [0.0, 0.06, 0.09, 0.14][tier])
		# 像素命中星（中 4 臂、重 8 臂，2 px 线、亮芯，三阶跳着消失）：小颗粒在后期满屏时读不出档位，靠它分轻重
		var sl: float = [0.0, 0.0, 0.08, 0.13][tier]
		g.fx.append({"kind": "hstar", "pos": head.round(), "r": [0.0, 0.0, 8.0, 14.0][tier], "col": col, "n": 4 if tier == 2 else 8, "life": sl, "max": sl, "ka": col.a})


## 击杀爆点按体型分档（docs/53，combat.kill 调用；纯画面 + 音效，粒子用 g.vrng，不碰 g.rng）：
## - 火花数 = fx/kill_sparks + e.r × fx/kill_sparks_per_r，速度随体型略增；冲击环照旧 e.r × 1.2
## - 大体型（e.r ≥ fx/kill_big_r）：再加一圈慢扩散的外环 + 脚下尘土 + 材质层音（甲壳 fx/kill_shell_sfx = kill_shell，其余 fx/kill_big_sfx = kill_big）
## - 击杀音 kill 的音高按体型降（fx/kill_pitch_r：r 越大越低），同屏一片小怪倒下时也听得出大小
## - 顿帧：大体型或暴击击杀 impact_pause(fx/kill_pause)，走共享预算（0.28 秒最多一次，受「命中顿帧」设置）
## lean：光学观感新击杀（combat.kill，光学观感开着时）——只留击杀音、材质层音与顿帧，火花 / 冲击环 / 尘土交给像素碎屑
func kill_burst(e: Dictionary, col: Color, crit: bool, lean := false) -> void:
	var r: float = float(e.get("r", 12.0))
	var rb: float = r / float(e.get("sc", 1.0))   # 怪物体型（spawner.escale）放大的按原体型判大小 / 火花数 / 音高 / 顿帧，爆点环按实际半径
	var big: bool = rb >= Bal.v("fx/kill_big_r", 16.0)
	var n: int = Bal.vi("fx/kill_sparks", 7) + int(rb * Bal.v("fx/kill_sparks_per_r", 0.3))
	# 后期降噪（render/declutter kill_k / kill_ring，缺省不变）：普通小怪的击杀火花随拥挤度减少、拥挤过半时不画小冲击环；
	# 火花只用 g.vrng，不碰对局随机数；精英 / Boss / 大体型照旧
	var plain: bool = not big and not e.get("elite", false) and not e.get("boss", false)
	if plain:
		n = maxi(1, int(round(n * Dc.at("kill_k", g.world.dcrowd))))
	if not lean:
		sparks(e.pos, Vector2.ZERO, col, n, 160.0 + r * 3.0)
	if not lean and (not plain or Dc.p("kill_ring") > 0.0 or g.world.dcrowd < 0.5):
		g.fx.append({"kind": "ring", "pos": e.pos, "r": r * 1.2, "life": 0.18, "max": 0.18, "col": col, "op_hit": true})
	var pitch: float = clampf(1.15 - rb / maxf(1.0, Bal.v("fx/kill_pitch_r", 60.0)), 0.75, 1.15)
	Sfx.play("kill", -8.0 + (2.0 if big else 0.0), pitch)
	if big:
		if not lean:
			g.fx.append({"kind": "ring", "pos": e.pos, "r": r * 2.0, "life": 0.3, "max": 0.3, "col": Color(col.r, col.g, col.b, 0.6), "op_hit": true})
			ground_dust(e.pos + Vector2(0, r * 0.6), r * 0.9, 7)
		var shell: bool = HIT_SHELL.has(e.get("type", ""))
		var fxs: Dictionary = Bal.sec("fx")
		var layer: String = str(fxs.get("kill_shell_sfx", "hit")) if shell else str(fxs.get("kill_big_sfx", "mire_splat"))
		if layer != "":
			Sfx.play(layer, -6.0 if shell else -8.0, 1.0, 0.05)   # 正式音 kill_shell / kill_big（gen_sfx_hitfeel.py）；缺文件时 sfx.ALT 借 hit ×0.6 / mire_splat ×0.85
	if big or crit:
		impact_pause(Bal.v("fx/kill_pause", 0.033))


## A low ring of slate-colored grit; capped so crowds do not bury silhouettes.
func ground_dust(p: Vector2, radius := 22.0, count := 7) -> void:
	if g.fx.size() > 380:
		return
	for i in mini(count, 12):
		var a: float = TAU * float(i) / float(maxi(count, 1))
		var direction := Vector2(cos(a), sin(a) * 0.4)
		g.fx.append({"kind": "spark", "pos": p + direction * radius * 0.35,
			"vel": direction * radius * 4.0, "life": 0.27, "max": 0.27,
			"col": Color(0.43, 0.51, 0.56, 0.75), "sz": 3.0 if i % 2 == 0 else 2.0})


## 直线弹撞上景物底座（地形阻挡，map.bullet_blocked）：反弹方向一小撮石屑 + 贴地扬尘
func rock_chip(p: Vector2, vel: Vector2) -> void:
	sparks(p, -vel if vel != Vector2.ZERO else Vector2.ZERO, Color(0.62, 0.66, 0.68, 0.9), 4, 130.0)
	ground_dust(p, 8.0, 4)


func _init(game: Game) -> void:
	g = game
	if Cfg.dev_args().has("--fxcensus"):
		_fxc = {}


## 播放美术交付的帧动画特效；素材不存在时返回 false，由调用方使用程序效果
func anim(name: String, pos: Vector2, dur: float, scale := Game.PX, follow := false) -> bool:
	if g.tex.get(name) == null:
		return false
	g.fx.append({"kind": "anim", "name": name, "pos": pos, "life": dur, "max": dur, "scale": scale, "follow": follow})
	return true


## 镜头震动已整体移除（看着头疼）：保留入口以免各处调用改动，一律不震
func shake_screen(_a: float) -> void:
	pass


func sparks(pos: Vector2, dir: Vector2, col: Color, n: int, spd: float) -> void:
	if g.fx.size() > 400:
		return
	n = maxi(1, int(round(n * Cfg.fx_density()))) if n > 0 else 0   # 低画质粒子减半（视觉，不影响模拟）
	for i in n:
		var a := g.vrng.randf() * TAU if dir == Vector2.ZERO else dir.angle() + g.vrng.randf_range(-0.7, 0.7)
		g.fx.append({"kind": "spark", "pos": pos, "vel": Vector2.from_angle(a) * spd * g.vrng.randf_range(0.4, 1.0),
			"life": g.vrng.randf_range(0.18, 0.32), "max": 0.3, "col": col, "sz": 2.0 if g.vrng.randf() < 0.6 else 4.0})


func blade_scale(sc: float) -> float:
	return minf(sc * BLADE_SCALE_K, BLADE_SCALE_MAX)


## 斩击贴图（覆盖约 126°，更宽的角度用多段拼接）
func slash_fx(origin: Vector2, ang: float, half: float, radius: float, col: Color, tex_name := "slash", life := 0.22) -> void:
	var span := 2.2
	var segs := int(ceil(half * 2.0 / span))
	var sc := radius / 22.0
	var frames := 4
	var anchor := Vector2(0.5, 0.5)
	if tex_name.begins_with("fx_umbrella_slash"):
		# V7 伞击帧条：6 帧，锚点 (4, h/2) 在伞柄，弧半径 = 帧宽 × 0.80，弧展开约 150°
		frames = 6
		var tx: Texture2D = g.tex[tex_name]
		var fw := float(tx.get_width()) / 6.0
		sc = radius / (fw * 0.80)
		anchor = Vector2(4.0 / fw, 0.5)
		span = 2.5
		segs = int(ceil(half * 2.0 / span))
	sc = blade_scale(sc)
	for k in segs:
		var a := ang
		if segs > 1:
			a = ang - half + span * 0.5 + (half * 2.0 - span) * float(k) / float(segs - 1)
		g.fx.append({"kind": "slash", "tex": tex_name, "pos": origin, "ang": a, "scale": sc, "life": life, "max": life, "col": col,
			"frames": frames, "anchor": anchor})


## 伞击贴图选择：有 V7 帧条就用，没有就退回旧 slash
func slash_tex(kind := "base") -> String:
	var n := "fx_umbrella_slash"
	if kind == "awaken":
		n += "_awaken"
	elif kind == "mirage":
		n += "_mirage"
	if g.tex.get(n) != null:
		return n
	if kind == "awaken" and g.tex.get("fx_s1_slash") != null:
		return "fx_s1_slash"
	if kind == "mirage" and g.tex.get("fx_s3_slash") != null:
		return "fx_s3_slash"
	return "slash"


## 飘字合并 / 限量（EA 1.1 后期降噪）：刚冒出（0.25 秒内）、同色同字号、离得近（28 以内）的纯数字飘字合成一个，
## 数字相加、重新计时、字号略放大；总数超过 TEXT_CAP 时丢掉最早的
const TEXT_CAP := 48
const TEXT_MERGE_R := 28.0
const TEXT_MERGE_T := 0.25

## 伤害数字（combat.damage 调用，docs/38 §1.15）：
## - 对 Boss：每 0.3 秒合并成一个数字（BOSS_SUM_T），暴击 / 弱点单独照常飘；
## - Boss 战期间，普通怪只飘暴击数字，普通伤害和弱点不飘（满屏数字会淹没招式名和预警）
const BOSS_SUM_T := 0.3
var _boss_sum: Array = []   # [{e, dmg, t, weak}]，按 is_same 找（字典内容会变，不能当键）

## render/mate_numbers 1（docs/139 §11）：队友 / 召唤物的伤害数字改小号、偏灰；队长的原样。对 Boss 的合并数字不分
func dmg_number(e: Dictionary, dmg: float, crit: bool, weak: bool, h := {}) -> void:
	if not Cfg.dmg_numbers or g.texts.size() >= 80:
		return
	var jit := Vector2(g.vrng.randf_range(-6, 6), 0)
	if Bal.vi("render/mate_numbers", 0) > 0 and not h.is_empty() and not is_lead_hit(h) and not e.boss:
		if crit:
			add_text(e.pos + jit + Vector2(0, -e.r - 10), str(int(round(dmg))), Color(0.85, 0.78, 0.6), 15)
			return
		if _boss_fight() or (not weak and g.texts.size() > _white_cap()):
			return
		add_text(e.pos + jit + Vector2(0, -e.r - 8), ("弱点 " if weak else "") + str(int(round(dmg))), Color(0.8, 0.72, 0.5) if weak else Color(0.72, 0.74, 0.78, 0.85), 13 if weak else 11)
		return
	var lk: float = g.world.lead_num_k if (g.world.lead_lv > 0 and not h.is_empty() and is_lead_hit(h)) else 1.0
	if lk > 1.0 and not e.boss:
		# 队长的伤害数字（docs/139 §11）：放大 lead_num_k、普通白字改暖白；暴击 / 弱点同样放大
		if crit:
			add_text(e.pos + jit + Vector2(0, -e.r - 12), str(int(round(dmg))), UI.GOLD, int(round(22 * lk)))
			return
		if _boss_fight() and not weak:
			return
		add_text(e.pos + jit + Vector2(0, -e.r - 10), ("弱点 " if weak else "") + str(int(round(dmg))), Color(1.0, 0.85, 0.35) if weak else Color(1.0, 0.93, 0.75), int(round((18.0 if weak else 15.0) * lk)))
		return
	if crit:
		add_text(e.pos + jit + Vector2(0, -e.r - 10), str(int(round(dmg))), UI.GOLD, 22)
		return
	if e.boss:
		for s in _boss_sum:
			if is_same(s.e, e):
				s.dmg += dmg
				s.weak = s.weak or weak
				return
		_boss_sum.append({"e": e, "dmg": dmg, "t": BOSS_SUM_T, "weak": weak, "brk": float(e.get("break_t", 0.0)) > 0.0})
		return
	if _boss_fight():
		return
	if weak and Dc.p("num_weak") < 1.0 and g.world.dcrowd > 0.5 and g.texts.size() > _white_cap():
		return   # 后期降噪 num_weak = 0：拥挤过半时「弱点 N」也和白字一样受上限（暴击 / 破绽照飘）
	if not weak and g.texts.size() > _white_cap():
		return   # 飘字多时普通白字不飘，只留暴击 / 弱点 / 破绽（可读性，1.1.1；后期上限随拥挤度降到 render/declutter num_cap）
	if weak:
		add_text(e.pos + jit + Vector2(0, -e.r - 12), "弱点 " + str(int(round(dmg))), Color(1.0, 0.85, 0.35), 18)
	else:
		add_text(e.pos + jit + Vector2(0, -e.r - 8), str(int(round(dmg))), Color(1, 1, 1, 0.95), int(round(14.0 * Dc.at("num_scale", g.world.dcrowd))))


## 普通白字伤害数字的同屏上限：fx/text_crowd（缺省 30），拥挤时按 render/declutter num_cap 插值（缺省 30 = 不变）
func _white_cap() -> int:
	var c0: float = Bal.v("fx/text_crowd", 30.0)
	return int(round(lerpf(c0, minf(c0, Dc.p("num_cap")), g.world.dcrowd)))


## 无敌时的提示（combat.damage 的 invuln 分支）：伊祖米克学习期飘「学习中」，其余无敌不飘（§1.15 删掉「无效」）
func immune_text(e: Dictionary) -> void:
	if e.get("type", "") == "izumik" and e.get("phase", 0) == 1 and g.texts.size() < 80 and g.vrng.randf() < 0.15:
		add_text(e.pos + Vector2(0, -e.r - 10), "学习中", Color(0.6, 0.85, 0.9), 13)


func _flush_boss_sum(dt: float) -> void:
	for s in _boss_sum:
		s.t -= dt
		if s.t > 0.0:
			continue
		var e: Dictionary = s.e
		if s.dmg >= 1.0 and s.get("brk", false):
			add_text(e.pos + Vector2(g.vrng.randf_range(-8, 8), -e.r - 16), ("" if g.combat.final_break_quiet(e) else "破绽 ") + str(int(round(s.dmg))), UI.GOLD, 22)   # 最终 Boss 不写「破绽」前缀（用户 10-28）   # 破绽期间：金色大一号（打击感审查）
		elif s.dmg >= 1.0 and (s.weak or g.texts.size() <= _white_cap()):
			add_text(e.pos + Vector2(g.vrng.randf_range(-8, 8), -e.r - 14), ("弱点 " if s.weak else "") + str(int(round(s.dmg))), Color(1.0, 0.85, 0.35) if s.weak else Color(1, 0.92, 0.95), 18)
	_boss_sum = _boss_sum.filter(func(s): return s.t > 0.0)


## 敌方特效标记（docs/48 全局 ③）：game.gd 在敌人 AI、敌弹与预警结算前后调用，给这两段里新加进 g.fx 的特效打上 enemy，
## render/world.gd 的后期降噪（fx_dim）跳过它们——敌人的爆炸、斩击、踏地、冲击环不该跟着友方特效一起变淡
func mark_enemy_fx(from: int) -> void:
	for i in range(from, g.fx.size()):
		g.fx[i]["enemy"] = true


## --textlog（docs/139 §9 量测，仅测试）：每条横幅请求 / 实播 / 左侧小字、每条非数字飘字打印一行 TEXTLOG <游戏秒> <类> <文字>
var _textlog := -1
func _tlog(kind: String, text: String) -> void:
	if _textlog < 0:
		_textlog = 1 if Cfg.dev_args().has("--textlog") else 0
	if _textlog == 1:
		print("TEXTLOG %.2f %s %s" % [g.t, kind, text.replace("
", " ")])


func add_text(pos: Vector2, text: String, col: Color, size := 14) -> void:
	var pn: Array = _num_parts(text)
	if pn.is_empty() and not text.is_valid_float():
		if not _word_ok(text):
			return
		_tlog("float", text)
	if not pn.is_empty():
		# 后期降噪（render/declutter num_merge_t / num_merge_r，缺省 = fx 段原值）：拥挤时合并窗口拉长、半径放大，同一片目标的数字并成一个
		var mt: float = lerpf(Bal.v("fx/text_merge_t", TEXT_MERGE_T), maxf(Bal.v("fx/text_merge_t", TEXT_MERGE_T), Dc.p("num_merge_t")), g.world.dcrowd)
		var mr: float = lerpf(Bal.v("fx/text_merge_r", TEXT_MERGE_R), maxf(Bal.v("fx/text_merge_r", TEXT_MERGE_R), Dc.p("num_merge_r")), g.world.dcrowd)
		for i in range(g.texts.size() - 1, maxi(-1, g.texts.size() - 25), -1):
			var t: Dictionary = g.texts[i]
			if t.max - t.life > mt or t.col != col or t.get("base", t.size) != size:
				continue
			if t.get("pos0", t.pos).distance_to(pos) > mr:
				continue
			var tp: Array = _num_parts(str(t.text))
			if tp.is_empty() or tp[0] != pn[0]:
				continue
			t["base"] = t.get("base", t.size)
			t.text = pn[0] + str(int(tp[1]) + int(pn[1]))
			t.size = mini(t.base + 6, t.size + 1)
			t.life = t.max
			return
	# 避让（可读性，1.1.1）：和刚冒出（text_nudge_t 秒内）的飘字框重叠就往上错一行，最多错 text_nudge_max 行
	var p0: Vector2 = pos
	var tries: int = Bal.vi("fx/text_nudge_max", 5)
	var nt: float = Bal.v("fx/text_nudge_t", 0.6)
	var w: float = _text_w(text, size)
	var moved := true
	while moved and tries > 0:
		moved = false
		for i in range(g.texts.size() - 1, maxi(-1, g.texts.size() - 30), -1):
			var t: Dictionary = g.texts[i]
			if t.max - t.life > nt:
				continue
			var tw: float = _text_w(str(t.text), int(t.size))
			if absf(t.pos.x - pos.x) < (tw + w) * 0.5 and absf(t.pos.y - pos.y) < (float(t.size) + size) * 0.5 + 1.0:
				pos.y = t.pos.y - (float(t.size) + size) * 0.5 - 2.0
				moved = true
				tries -= 1
				break
	g.texts.append({"pos": pos, "pos0": p0, "text": text, "col": col, "life": 0.65, "max": 0.65, "size": size})
	if g.texts.size() > TEXT_CAP:
		g.texts.pop_front()


## 可合并的数字飘字：["前缀", "数字"]（纯数字前缀为空；「弱点 94」「破绽 382」按前缀分开合并），其余返回 []
func _num_parts(text: String) -> Array:
	if text.is_valid_int():
		return ["", text]
	for pre in ["弱点 ", "破绽 "]:
		if text.begins_with(pre) and text.substr(pre.length()).is_valid_int():
			return [pre, text.substr(pre.length())]
	return []


## 飘字宽度估算（世界坐标；中文按 1 个字号、数字 / 空格按 0.66 个字号，外加描边 8）
func _text_w(text: String, size: int) -> float:
	var w := 8.0
	for ch in text:
		w += size * (0.66 if ch.unicode_at(0) < 256 else 1.0)
	return w


func update(dt: float) -> void:
	g.flash = maxf(0.0, g.flash - dt * 2.0)
	g.horde_warn = maxf(0.0, g.horde_warn - dt)
	g.tab_hint = maxf(0.0, g.tab_hint - dt)
	g.horde_hit = maxf(0.0, g.horde_hit - dt)
	g.lvup_show -= dt
	g.hud_lv_flash = max(0.0, g.hud_lv_flash - dt * 1.5)
	g.xp_flash = maxf(0.0, g.xp_flash - dt * 3.0)
	for f in g.fx:
		f.life -= dt
		if f.has("shatter") and f.life <= 0.0:
			_shatter(f)
		if f.kind == "spark" or f.kind == "shard":
			f.pos += f.vel * dt
			f.vel *= 0.9
		elif f.kind == "mote":
			# 光尘（docs/54）：带重力 / 阻力的小方块，按游戏时间推进；drag 按秒算（0.9^dt 近似）
			f.vel.y += f.grav * dt
			f.vel *= maxf(0.0, 1.0 - f.drag * dt)
			f.pos += f.vel * dt
	for f in g.texts:
		f.life -= dt
		f.pos.y -= 30.0 * dt
	_update_banner_queue(dt)
	_flush_boss_sum(dt)


## 横幅队列（EA 1.1，docs/38 B0 第 8 条的横幅部分，Boss与怪物同意由界面接手）：
## - 优先级 prio：3 Boss 登场 / 换阶段 > 2 黑潮、生命垂危 > 1 普通（精英、商人、威胁等局内事件）> 0 提示（干员技能名、入队、精英化、音乐开关）。
##   调用方可以传 show_banner(text, prio)；不传时按文字猜（Boss 名、「黑潮」「生命垂危」、提示类关键词）；干员脚本经 op_api 一律传 0
## - prio 0 的提示只在空闲时显示，有横幅在播就直接丢掉、不排队（干员技能名反复触发，排队会把精英出现这类事件挤掉）
## - 同时只显示一条；优先级更高的立即顶掉当前这条，否则排队，队列最多 3 条（满了丢优先级最低里最旧的）
## - 去重：和正在显示的、队列里的都比，同一句不重复排
## - 选卡 / 商人面板打开时 game.gd 暂停 banner_t，队列也跟着停（本函数只在 PLAY 里跑），关掉后一条播完才轮到下一条
## - 大群来袭的大横幅在场时，普通横幅先停住（计时冻结、不画），Boss 横幅照常画在大群横幅下方
## - Boss 战期间，prio ≤ 1 的改成左侧小字通知（notices），不占屏幕中间
## - 同一局第二次起的同一句（反复放的技能名「潮汐」「审判」…）改成小横幅、1.5 秒
const BANNER_Q_MAX := 3
const NOTICE_MAX := 4
const NOTICE_LIFE := 4.0
const HINT_WORDS := ["加入编队", "加入支援", "升至 Lv", "晋升至精英", "音乐："]
var banner_seen := {}
var banner_small := false
var banner_prio := 0
var banner_serial := 0            # 每换一条横幅 +1（hud_banners 据此重放字距收拢动效，docs/62 §3.10）
var banner_q: Array = []          # [{text, prio}]
var notices: Array = []           # [{text, t}]
var banner_log: Array = []        # 本局请求过的横幅文字（按调用顺序，最多 64 条；回归测试数「某句播了几次」用）
var _boss_words: Array = []

func show_banner(text: String, prio := -1) -> void:
	_tlog("req%d" % (prio if prio >= 0 else _guess_prio(text)), text)
	banner_log.append(text)
	if banner_log.size() > 64:
		banner_log.pop_front()
	if prio < 0:
		prio = _guess_prio(text)
	match _calm_route(text, prio):
		"drop":
			return
		"notice":
			_notice(text)
			return
	if prio <= 1 and _boss_fight():
		_notice(text)
		return
	if g.banner_t > 0.0 and g.banner == text:
		return
	if prio == 0 and g.banner_t > 0.0:
		return
	for q in banner_q:
		if q.text == text:
			return
	if (g.banner_t <= 0.0 and _gap_ok(prio)) or prio > banner_prio:
		_banner_now(text, prio)
		return
	banner_q.append({"text": text, "prio": prio})
	banner_q.sort_custom(func(a, b): return a.prio > b.prio)   # sort_custom 不稳定也无妨：同级顺序只影响先后
	while banner_q.size() > BANNER_Q_MAX:
		banner_q.pop_back()


## ── 文字提醒节流（docs/139 §9，用户 10-25「那些字提醒的时候也显得太频繁了」；10-29 起常开，旧开关 render/text_calm 已删）──
## 横幅只给要玩家做事的（黑潮、Boss、商人到达、精英、灯标）；状态变化 / 干员提示改左侧小字（notices）或不显示；
## 同类横幅有冷却（BANNER_CD，冷却中改小字），两条横幅之间至少 render/banner_gap 秒（黑潮 / Boss 横幅不受限；其余排队等）；
## 头顶文字飘字（非数字）：同一句 render/word_gap 秒内只出一次、同屏最多 render/word_max 条，敌人「狂暴」「尖叫」不再飘字（本体已有变色 / 光环）
const BANNER_CD := {"elite": 45.0, "beacon": 90.0, "tide": 25.0, "same": 60.0}
const WORD_DROP := ["狂暴", "尖叫", "架起结束"]
var _cat_t := {}
var _last_banner_ms := -100000.0
var _word_t := {}

## 横幅分流：show（照常横幅）/ notice（左侧小字）/ drop（不显示）
func _calm_route(text: String, prio: int) -> String:
	if prio >= 2:
		return "show"   # 黑潮 / 生命垂危 / Boss：要玩家立刻做事
	if prio == 0:
		for w in HINT_WORDS:
			if w in text:
				return "notice"   # 入队 / 升级 / 精英化 / 音乐：状态变化，左侧小字
		return "drop"   # 干员技能名：头顶已有施放飘字
	if text.begins_with("商人收好") or text.begins_with("威胁上升") or "熔铸" in text or text.begins_with("排异反应") or text.begins_with("探索的走向"):
		return "notice"
	var cat := "same:" + text
	if text.begins_with("精英「"):
		cat = "elite"
	elif text.begins_with("引航灯标"):
		cat = "beacon"
	var cd: float = BANNER_CD.get(cat.split(":")[0], BANNER_CD.same)
	var now: float = g.t
	if now - float(_cat_t.get(cat, -1000.0)) < cd:
		return "notice"
	_cat_t[cat] = now
	return "show"


func _word_ok(text: String) -> bool:
	if text in WORD_DROP:
		return false
	var now: float = g.t
	if now - float(_word_t.get(text, -1000.0)) < Bal.v("render/word_gap", 15.0):
		return false
	var live := 0
	for t in g.texts:
		if t.life > 0.0 and _num_parts(str(t.text)).is_empty():
			live += 1
	if live >= Bal.vi("render/word_max", 4):
		return false
	_word_t[text] = now
	return true


## 两条横幅之间的最小间隔（游戏秒；黑潮 / Boss 横幅不受限）
func _gap_ok(prio: int) -> bool:
	return prio >= 2 or g.t - _last_banner_ms >= Bal.v("render/banner_gap", 8.0)


func _banner_now(text: String, prio: int) -> void:
	_last_banner_ms = g.t
	_tlog("show%d%s" % [prio, "s" if banner_seen.has(text) else ""], text)
	g.banner = text
	banner_serial += 1
	banner_prio = prio
	banner_small = banner_seen.has(text)
	banner_seen[text] = true
	g.banner_t = 1.5 if banner_small else 3.0


func horde_band_on() -> bool:
	return g.horde_warn > 0.0 or g.horde_hit > 0.0


func _update_banner_queue(dt: float) -> void:
	if g.mode == Game.Mode.BALANCE:
		g.banner_t -= dt   # 平衡 / 自测模式每渲染帧跑多步模拟：横幅按游戏时间计时，截图里的停留和排队延迟才像真人（game.gd 按真实时间再减一次，影响很小）
	if g.banner_t > 0.0 and horde_band_on() and banner_prio < 3:
		g.banner_t += dt   # 大群横幅在场：普通横幅冻结，等大群横幅退场再播完
	if g.banner_t <= 0.0 and not banner_q.is_empty() and _gap_ok(int(banner_q[0].prio)):
		var q: Dictionary = banner_q.pop_front()
		_banner_now(q.text, q.prio)
	for n in notices:
		n.t -= dt
	notices = notices.filter(func(n): return n.t > 0.0)


func _notice(text: String) -> void:
	_tlog("notice", text)
	for n in notices:
		if n.text == text:
			n.t = NOTICE_LIFE
			return
	notices.append({"text": text, "t": NOTICE_LIFE})
	while notices.size() > NOTICE_MAX:
		notices.pop_front()


func _boss_fight() -> bool:
	for b in g.bosses:
		if not b.dead and D.ENEMIES.get(b.type, {}).get("role", "") == "boss":   # 召唤物 / 分身不算 Boss 战
			return true
	return false


func _guess_prio(text: String) -> int:
	if _boss_words.is_empty():
		for k in D.ENEMIES:
			var e: Dictionary = D.ENEMIES[k]
			if e.get("role", "") == "boss":
				_boss_words.append(str(e.get("name", k)).split("，")[0].replace("\"", ""))
		_boss_words.append("骑士")
	for w in _boss_words:
		if w != "" and w in text:
			return 3
	if "阶段" in text or "形态" in text:
		return 3
	if "黑潮" in text or "生命垂危" in text:
		return 2
	for w in HINT_WORDS:
		if w in text:
			return 0
	return 1


## 按敌人材质播放命中效果（V7 缺图时退回 fx_hit）
func hit_fx(e: Dictionary, dir := Vector2.ZERO) -> void:
	var n := "fx_hit_flesh"
	if HIT_SHELL.has(e.type):
		n = "fx_hit_shell"
	elif HIT_SPIRIT.has(e.type) or e.get("hover", false):
		n = "fx_hit_spirit"
	var sc: float = Game.PX * clampf(e.r / 12.0, 0.9, 2.2)
	if not fx_sprite(n, e.pos + Vector2(0, -e.r * 0.5), sc, dir.angle() if dir != Vector2.ZERO else g.vrng.randf() * TAU):
		anim("fx_hit", e.pos, 0.16)


## 激光三段：起点（枪口）+ 平铺中段（末段按长度裁切，不拉伸）+ 末端光斑
func spr_rot(name: String, frame: int, pos: Vector2, ang: float, scale := Game.PX, col := Color.WHITE, anchor_px := Vector2(-1, -1), flip := false) -> void:
	var tx: Texture2D = g.tex.get(name)
	if tx == null:
		return
	var frames: int = Game.V6_FRAMES.get(name, [1, 0.0])[0]
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	var an := anchor_px if anchor_px.x >= 0.0 else Vector2(fw, fh) / 2.0
	scale /= A.hires_of(tx)   # @2x 高清帧条（Codex fx30）：同一逻辑尺寸，像素密度加倍
	g.draw_set_transform(pos + g.draw_off, ang, Vector2(-scale if flip else scale, scale))
	g.draw_texture_rect_region(tx, Rect2(-an, Vector2(fw, fh)), Rect2(fw * (frame % frames), 0, fw, fh), FD.capc(col))
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 一次性帧动画特效（命中 / 爆炸）；素材不存在时返回 false，调用方回退到程序特效
## 播放一条帧条特效：flip 镜像；bottom=true 时 pos 为脚底（帧条底部对齐）
## 普通敌人击杀溶解染成淡紫（docs/48 P1：击杀溶解、经验结晶、敌人描边都是青色，后期连成一片）：
## 经验结晶留青色（拾取物），溶解偏紫、描边偏中性白
const DISSOLVE_TINT := Color(1.0, 0.72, 1.05)

## ground=true：地面层帧条（kind "gsprite"，world._draw_ground_sprites 在溟痕之后、预警之前画；敌方落点溅射 / 囊液残留，docs/96）；
## anchor_px：帧内原点（1x 美术像素，按贴图密度换算；manifest 的 origin_1x），缺省帧中心
## delay：晚这么多秒才开始播（期间不画、不补光学火星；维什戴尔大爆炸的连环外圈，docs/137 §8）
var spawn_lead := false   # squad.update 在队长更新期间置真：这期间生成的帧条特效打上 lead（world 绘制时按突出队长档提亮，docs/139 §11）

func fx_sprite(name: String, pos: Vector2, scale := Game.PX, ang := 0.0, flip := false, bottom := false, col := Color.WHITE, ground := false, anchor_px := Vector2(-1, -1), delay := 0.0) -> bool:
	if _fxc != null:
		_fx_census(name, ground)
	if g.tex.get(name) == null:
		return false
	if name.begins_with("fx_slash") or name.begins_with("fx_claw"):
		scale = blade_scale(scale)
	scale = minf(scale, FX_SCALE_MAX)
	if name == "fx_death_dissolve" and col == Color.WHITE:
		col = DISSOLVE_TINT
	var spec: Array = Game.V6_FRAMES[name]
	var dur: float = spec[0] / spec[1]
	if _fxc != null:
		_fx_census("SC|%s|%.3f" % [name, scale / A.hires_of(g.tex[name])], ground)   # 每个贴图像素占几个世界像素（÷2 = 低分辨率层格数）
	var f := {"kind": "gsprite" if ground else "sprite", "name": name, "pos": pos, "ang": ang, "scale": scale, "life": dur + delay, "max": dur + delay, "flip": flip, "col": col}
	if spawn_lead:
		f["lead"] = true
	if delay > 0.0:
		f["delay"] = delay
	if bottom:
		var tx: Texture2D = g.tex[name]
		f["anchor"] = Vector2(tx.get_width() / spec[0] / 2.0, tx.get_height() - 1.0)
	elif anchor_px.x >= 0.0:
		f["anchor"] = anchor_px * A.hires_of(g.tex[name])
	if not ground and delay <= 0.0 and g.optical_on and g.optical != null and g.optical.grains != null:
		var texture: Texture2D = g.tex[name]
		var origin: Vector2 = f.get("anchor", Vector2(texture.get_width() / spec[0], texture.get_height()) / 2.0)
		if g.optical.grains.material_burst(name, texture, int(spec[0]), pos, ang, scale / A.hires_of(texture), origin, flip, col):
			var kind: String = g.optical.grains.MATERIAL_FX[name]
			if kind == "water":
				# 水体保留紧凑半透明核心，外围由颗粒承担；不再追加 GPU 爆发。
				f["scale"] = scale * 0.72
				f["col"] = Color(col.r, col.g, col.b, col.a * 0.6)
			elif kind == "fire" or kind == "lava":
				# 保留火焰核心；外围余烬收拢，不增加粒子数。
				f["scale"] = scale * 0.78
				f["col"] = Color(col.r, col.g, col.b, col.a * 0.65)
			else:
				f["kind"] = "grain_light"
				f["life"] = 0.24
				f["max"] = 0.24
			g.fx.append(f)
			return true
	g.fx.append(f)
	if g.optical_on and g.optical.fx1 and not ground and delay <= 0.0 and g.optical.particles != null and not name.ends_with("_death"):   # 死亡帧条不喷（docs/130 C1：击杀吃掉技能火星的限频）
		g.optical.particles.fx_burst(name, pos, scale)   # 光学观感 ③：按这条帧条的本色补火星 / 碎片（限频、有上限）
	return true


## 以美术像素为单位绘制横向帧条中的一帧，anchor 为贴图内的锚点（0~1）
func spr(name: String, frames: int, frame: int, pos: Vector2, scale := Game.PX, flip := false, col := Color.WHITE, anchor := Vector2(0.5, 0.5), sq := Vector2.ONE) -> void:
	var tx: Texture2D = g.tex.get(name)
	if tx == null:
		return
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	FD.blit(g, tx, FD.src(fw, fh, frames, frame), pos + g.draw_off, Vector2(fw, fh) * scale * sq, anchor, flip, col)   # flip：以锚点为轴水平镜像


func draw_add_layer() -> void:
	g.draw_off = Vector2.ZERO
	if Look.dbg("nogod") == "":
		g.map.draw_god_rays(g.fx_add, g.view_size(), g.cam.position)
	var loop := int(g.t * 10.0)
	g.squad.draw_fx_add(g.fx_add, loop)
	draw_glows(g.fx_add)   # docs/54 柔光（灯标点燃 / 升级 / 晋升 / 拾取 / 精英登场 / 商人）
	for f in g.fx:
		if f.kind != "anim":
			continue
		var n: int = Game.FXF.get(f.name, 1)
		var fr := clampi(int((1.0 - f.life / f.max) * n), 0, n - 1)
		var p: Vector2 = g.ppos if f.follow else f.pos
		spr_on(g.fx_add, f.name, n, fr, p, f.scale)


## 同 _spr，但画在指定节点上（用于叠加发光层）
func spr_on(ci: CanvasItem, name: String, frames: int, frame: int, pos: Vector2, scale := Game.PX) -> void:
	var tx: Texture2D = g.tex[name]
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	FD.blit(ci, tx, FD.src(fw, fh, frames, frame), pos, Vector2(fw, fh) * scale, Vector2(0.5, 0.5), false, Color.WHITE)


## Boss 扩展招式只负责外观；伤害和弹幕由 BossPatterns 结算。
# Purely cosmetic identity; warning geometry and damage stay in BossAI.
## 出招签名特效；颜色 = Boss 专属色（enemies.json bcol，docs/142b §8.4，协调人 10-25：专属色表写 json）
const BOSS_STYLE := {
	"carmen": "fx_muzzle_flash",
	"iberia": "fx_muzzle_flash",
	"path": "fx_circle_steel",
	"bishop": "fx_water_splash",   # 青绿水花和靛蓝不搭：Boss 颗粒开着时不放（同伊祖米克）
	"archon": "fx_claw_double_green",
	"immortal": "fx_slash_arc_deep",
	"paranoia": "fx_circle_ghost",
	"knight_boss": "fx_knight_impact",
	"ishar": "fx_water_splash",
	"izumik": "fx_felspell",   # 绿色邪能，和群青不搭：Boss 颗粒开着时不放（boss_signature），由结算颗粒出专属色
}

func boss_color(type: String) -> Color:
	return D.ENEMIES.get(type, {}).get("bcol", Color(1.0, 0.3, 0.65))

func boss_signature(w: Dictionary) -> void:
	var e: Dictionary = w.owner
	if e.type == "knight_boss" and w.get("skin", "") in ["ice_wave","ice_thrust","ice_field","ice_lance","ice_wall"]: return
	if not BOSS_STYLE.has(e.type):
		return
	var start := g.fx.size()
	var pos: Vector2 = w.pos
	if e.type in ["carmen", "iberia"]:
		pos = e.pos + Vector2.from_angle(w.get("ang", 0.0)) * 28.0 + Vector2(0, -18)
	if not (e.type in ["izumik", "bishop"] and BossBeam.grains(g) != null):   # 用户 10-25：伊祖米克那团荧光绿不搭；主教的青绿水花和靛蓝同理
		fx_sprite(BOSS_STYLE[e.type], pos, 2.0)
	g.fx.append({"kind": "ring", "pos": pos, "r": 40.0, "life": 0.3, "max": 0.3, "col": boss_color(e.type)})
	for i in range(start, g.fx.size()):
		g.fx[i]["enemy"] = true

func boss_pattern(w: Dictionary) -> void:
	boss_signature(w)
	var start: int = g.fx.size()
	var dir := Vector2.from_angle(w.ang)
	match str(w.act):
		"pattern_cleave":
			slash_fx(w.pos, w.ang, w.half, w.r, w.col, "slash", 0.32)
			fx_sprite(w.pattern.get("texture", "fx_slash_arc_rose"), w.pos + dir * w.r * 0.5, 2.8, w.ang)
			Sfx.play("swing", -4.0, 0.7)
		"pattern_line":
			g.fx.append({"kind": "tracer" if w.owner.type in ["iberia", "carmen", "knight_boss"] else "bbeam",
				"a": w.pos, "b": w.pos + dir * w.len, "life": 0.28, "max": 0.28, "col": w.col, "wid": w.wid})
			Sfx.play("hit", -5.0, 0.7, 0.0)
		"pattern_rain":
			g.fx.append({"kind": "wpillar", "pos": w.pos, "r": w.r, "life": 0.5, "max": 0.5, "col": w.col})
			# 2.5 倍水花贴图会被材质颗粒拆成一团荧光绿，7 个落点连成一片（用户 10-25「绿色的那团不搭、糊成一整团」）：
			# Boss 颗粒开着时不放，水柱由结算颗粒出专属色颗粒（有上限、有明暗）；关着时照旧
			if not (w.owner.get("boss", false) and BossBeam.grains(g) != null):
				fx_sprite("fx_water_splash", w.pos, 2.5)
			Sfx.play("tentacle", -7.0, 0.9)
		_:
			g.fx.append({"kind": "ring", "pos": w.pos, "r": 40.0, "life": 0.3, "max": 0.3, "col": w.col})
			Sfx.enemy("spit", w.pos.distance_to(g.ppos))
	for i in range(start, g.fx.size()):
		g.fx[i]["enemy"] = true


# 用户确认复用水月旧版深渊月牙帧条，运行时换色，原始素材保持不变。
var blade_palettes: Dictionary = {}
func boss_blade(b: Dictionary, pos: Vector2) -> void:
	var type: String = b.get("src_type", "paranoia")
	if not blade_palettes.has(type):
		var original: Texture2D = g.tex.get("proj_tide_blade_abyss")
		if original == null:
			return
		var pixels := original.get_image()
		var tint := boss_color(type)
		for y in pixels.get_height():
			for x in pixels.get_width():
				var c := pixels.get_pixel(x, y)
				if c.a > 0.0:
					pixels.set_pixel(x, y, Color.from_hsv(tint.h, c.s * tint.s, c.v, c.a))
		blade_palettes[type] = ImageTexture.create_from_image(pixels)
	var tx: Texture2D = blade_palettes[type]
	var size := Vector2(tx.get_width() / 4.0, tx.get_height())
	var frame := int(g.t * 12.0) % 4
	# 刃缘与原先约 30px 高的弹幕一致，原图拖尾也一起保留。
	var scale := 36.0 / size.y
	g.draw_set_transform(pos + g.draw_off, b.vel.angle(), Vector2.ONE * scale)
	g.draw_texture_rect_region(tx, Rect2(-size * 0.5, size), Rect2(Vector2(frame * size.x, 0), size))
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# =====================================================================
# 画面特效二轮（docs/54，界面与美术 2026-10-10）：环境与事件特效，不含打击反馈（docs/53）与 Boss 登场。
# 全部纯画面：只往 g.fx 追加、只用 g.vrng；旋钮在 data/balance.json 的 fx 段（10-29 起各项常开，旧开关 fx/vfx2 与各单项开关已删）；
# 低画质 / 触屏不画常驻环境粒子（ambient_ok），一次性事件粒子按 Cfg.fx_density 减半。
# 新增的 fx 种类：mote（光尘，tb 批）、glow（加色层的柔光，light 贴图）、mire_recoil（溟痕退散的收缩环）
# =====================================================================
var _fxc = null                # --fxcensus（docs/138 §7）：本局经 fx_sprite 播过的帧条名 → 次数，局终 / 每 30 秒打印 FXCENSUS（盘点可粒子化的一次性特效）
var _fxc_t := 0.0
var _int_on := false            # 低分辨率层整数格（docs/138 §10）：每帧按 render/fx_int_scale + 光学低分辨率层是否开着刷新一次
var _int_f := -1
var p2 := true                 # 运行时总开关（--vfxab=N 同局轮换测量用；缺省开）
var _k2: Dictionary = {}       # fx 段快照（每帧读的旋钮不走 Bal.v 的字符串拆分）
var _lamp_prev := -1.0         # 灯火观察（update_visuals 调 watch_lamp）
var _lamp_ember_acc := 0.0
var _merchant_acc := 0.0
var _elite_seen := {}
var _sight := {}               # docs/54 §7「首次入画」：精英 id → 登场动画起点（g.t）
var _merchant_seen := false     # 商人本次出现是否已入画（入画那一帧放出现特效）
## docs/54 §6 的五条帧条（tools/gen_fx_strips.py）：有图就用图，没图走下面各处原来的程序画法；fx/strips = 0 强制走程序画法
const STRIPS := ["fx_beacon_ignite", "fx_ember", "fx_mire_dissolve", "fx_levelup_pillar", "fx_elite_spawn"]

## world 视图（game.gd 的 world 成员与本文件互相 preload，带类型访问会解析失败，取动态引用）
func _wv():
	return g.get("world")

func _kv(name: String, d: float) -> float:
	if _k2.is_empty():
		_k2 = Bal.sec("fx")
		if _k2.is_empty():
			_k2 = {"_": 0}
	var v = _k2.get(name)
	return float(v) if (v is float or v is int) else d


## 帧条贴图在且允许用（fx/strips 旋钮，缺省 1）
func strip(name: String) -> bool:
	return g.tex.get(name) != null and _kv("strips", 1.0) > 0.0


## 加色层上的一次性帧条（fx_beacon_ignite / fx_levelup_pillar）：anchor 为帧内锚点（像素），draw_glows 画
func add_strip(name: String, pos: Vector2, scale: float, col: Color, anchor: Vector2) -> void:
	if g.fx.size() > 440:
		return
	var spec: Array = Game.V6_FRAMES[name]
	var dur: float = spec[0] / spec[1]
	g.fx.append({"kind": "aspr", "name": name, "pos": pos, "scale": scale, "col": col, "anchor": anchor, "life": dur, "max": dur})


## 「首次入画」（docs/54 §7 第 2–3 条；10-29 起常开，旧开关 fx/first_sight 已删）：精英登场 / 商人出现的特效改在实体第一次进入视野时播，
## 而不是刷出（多在屏外）那一刻；刷出时就在视野内则和原来一样从刷出算起。纯画面状态，不碰 g.rng
## 精英本帧要不要走登场动画（world 每帧按视野内的精英调）：首次入画起 0.9 秒内为真
func elite_entrance_due(e: Dictionary) -> bool:
	var key: int = int(e.get("id", 0))
	if not _sight.has(key):
		if _sight.size() > 128:
			_prune_sight()
		_sight[key] = g.t - minf(float(e.get("age", 0.0)), 0.9)   # 刷出时已在视野内：从刷出算起（同改动前）
	return g.t - float(_sight[key]) < 0.9


func _prune_sight() -> void:
	var live := {}
	for e in g.enemies:
		live[int(e.get("id", 0))] = true
	for k in _sight.keys():
		if not live.has(k):
			_sight.erase(k)


## 常驻环境粒子（溟痕光尘、低灯火余烬、商人灯笼）：低画质和触屏设备不画
func ambient_ok() -> bool:
	return p2 and Cfg.quality != "low" and not Cfg.touch_device()


## 光尘：n 粒从 pos 出发，基础方向 dir（ZERO = 全向）× spd，带重力 grav（负 = 上浮）与阻力 drag（1/秒）
## em = true：余烬，有 fx_ember 帧条时按剩余寿命播 4 帧（颜色仍按 col 调制），没有照旧画方块
func motes(pos: Vector2, dir: Vector2, col: Color, n: int, spd: float, life: float, grav := 0.0, drag := 1.5, sz := 2.0, spread := 0.6, scatter := 0.0, em := false) -> void:
	if g.fx.size() > 420 or n <= 0:
		return
	n = maxi(1, int(round(n * Cfg.fx_density())))
	for i in n:
		var a: float = g.vrng.randf() * TAU if dir == Vector2.ZERO else dir.angle() + g.vrng.randf_range(-spread, spread)
		var p: Vector2 = pos
		if scatter > 0.0:
			p += Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(0.0, scatter)
		g.fx.append({"kind": "mote", "pos": p, "vel": Vector2.from_angle(a) * spd * g.vrng.randf_range(0.35, 1.0),
			"life": life * g.vrng.randf_range(0.6, 1.0), "max": life, "col": col, "grav": grav, "drag": drag,
			"sz": sz if g.vrng.randf() < 0.7 else sz * 1.6, "em": em and strip("fx_ember")})


## 加色层柔光：半径 r，life 秒内先胀后淡（grow：起始半径比例）
func glow(pos: Vector2, r: float, col: Color, life: float, grow := 0.6) -> void:
	if g.fx.size() > 440:
		return
	g.fx.append({"kind": "glow", "pos": pos, "r": r, "col": col, "life": life, "max": life, "grow": grow})


## ① 灯标点燃（world.beacon_burst 调用；原有的爆闪 / 扩环 / 放射线 / 火花照旧）：
## 灯室柔光一片、余烬上升、被清掉的溟痕收缩退散（beacon._light 记在 b.cleared 里的 [pos, r]）
func beacon_ignite(b: Dictionary) -> void:
	if not p2:
		return
	var pos: Vector2 = b.get("pos", Vector2.ZERO)
	var lamp: Vector2 = pos + Vector2(0, -62.0)
	var cr: float = float(b.get("clear_r", 260.0))
	glow(lamp, cr * 0.9, Color(1.0, 0.86, 0.6, 0.55), 1.1, 0.25)
	if strip("fx_beacon_ignite"):
		# 点燃帧条（64×64 × 8，16 fps，加色层）盖在灯室上，代替程序画的白芯柔光；大片暖光照旧
		add_strip("fx_beacon_ignite", lamp, Game.PX, Color(1.0, 0.95, 0.85, 0.95), Vector2(32, 32))
	else:
		glow(lamp, 70.0, Color(1.0, 0.95, 0.8, 0.9), 0.45, 0.5)
	motes(lamp, Vector2.UP, Color(1.9, 1.5, 0.8), Bal.vi("fx/beacon_embers", 28), 150.0, 1.6, -40.0, 1.2, 2.0, 0.9, 0.0, true)
	motes(pos, Vector2.ZERO, Color(1.7, 1.3, 0.7, 0.9), int(Bal.vi("fx/beacon_embers", 28) / 2), 220.0, 1.0, -120.0, 2.5, 2.0, 0.0, 40.0, true)
	var cleared: Array = b.get("cleared", [])
	if not cleared.is_empty():
		# tex = true：每片溟痕按 fx_mire_dissolve（64×64 × 6，8 fps = 0.75 秒）播退散，world 不再画收缩环
		# 10-26：自中心向外扫开（每片带延迟，beacon._light 写），总长 = 扫到圈边 sweep_t + 每片碎散 pd，约 0.55 秒
		var st: float = Bal.v("beacon/sweep_t", 0.3)
		var pd: float = 0.25
		g.fx.append({"kind": "mire_recoil", "pts": cleared.slice(0, 40), "from": pos, "life": st + pd, "max": st + pd, "pd": pd, "sweep_r": cr, "sweep_t": st, "tex": strip("fx_mire_dissolve")})
		for c in cleared.slice(0, 8):
			motes(c[0], Vector2.UP, Color(0.9, 0.55, 1.4, 0.8), 4, 60.0, 0.9, -30.0, 1.0, 2.0, 1.2, float(c[1]) * 0.5)


## ② 升级（pickups.levelup_fx 调用；原有的双环 + 18 火花 + 头顶字样照旧）：主控柔光 + 金色光柱 + 上升光尘 + 轻微全屏白闪
func levelup_burst(pos: Vector2) -> void:
	if not p2:
		return
	glow(pos + Vector2(0, -24), 170.0, Color(1.0, 0.85, 0.45, 0.6), 0.55, 0.5)
	if strip("fx_levelup_pillar"):
		# 光柱帧条（32×160 × 6，12 fps，加色层，脚底对齐；按 0.75 倍画成 240 高，免得盖到半屏）
		add_strip("fx_levelup_pillar", pos + Vector2(0, 8), Game.PX * 0.75, Color(1.0, 0.92, 0.7, 0.9), Vector2(16, 159))
	else:
		g.fx.append({"kind": "pillar", "pos": pos + Vector2(0, 8), "life": 0.55, "max": 0.55, "col": Color(1.0, 0.85, 0.4)})
	motes(pos + Vector2(0, -10), Vector2.UP, Color(2.0, 1.7, 0.9), Bal.vi("fx/levelup_motes", 24), 140.0, 1.3, -60.0, 1.0, 2.0, 1.1, 22.0, true)
	g.flash = maxf(g.flash, Bal.v("fx/levelup_flash", 0.25))


## 升级光爆（TA 审阅 docs/208 H2，10-31：原来同心双圈 + 光柱帧条 + 柔光 + 火花叠在一起，「圈、发白、拼接」三样全占）：
## 改成一次性干净主体——脚下白金爆亮 0.08 秒 → 金色光粒迸开（短、阻力大）→ 上升青色光尘；
## 脚底一道不规整的尘浪环（fx_ul_dust_ring，每次按哈希换转角 / 镜像 / 大小）往外推开、从暖白冷成青灰淡掉，不画正圆描边。开关 fx/levelup_v2（缺省 1），
## 终结技框架（g.ult，借它的帧条 / 光照）关着时返回 false，调用方退回旧版。纯画面，随机只走 g.vrng（光尘）与哈希
const LVUP_GOLD := Color(1.0, 0.86, 0.5)
const LVUP_CYAN := Color(0.55, 0.95, 1.0)


func levelup_burst_v2(pos: Vector2) -> bool:
	var u = g.ult
	if u == null or Bal.v("fx/levelup_v2", 1.0) <= 0.0 or not p2 or not u.fx_ready("fx_ul_dust_ring"):
		return false
	var hh: float = fposmod(sin(g.t * 12.9898 + pos.x * 0.078 + pos.y * 0.033) * 43758.5453, 1.0)   # 每次升级的变体（哈希，不抽模拟随机数）
	var c: Vector2 = pos + Vector2(0, -18)
	u.shape({"kind": "circle", "c": c, "r": 30.0, "col": Color(1.0, 0.95, 0.82), "fill": 0.85, "life": 0.08})   # 爆亮 2–3 帧
	var t: Texture2D = u._strip_tex("fx_ul_dust_ring")
	var rr: float = t.get_width() * 0.5 / A.hires_of(t) * g.PX
	u.strip("fx_ul_dust_ring", pos + Vector2(0, 4), {"layer": "back", "sc": 30.0 / rr, "sc1": (150.0 + 40.0 * hh) / rr, "scd": 0.3, "life": 0.5, "fade": 0.3,
		"ang": hh * TAU, "sx": -1.0 if hh < 0.5 else 1.0, "col": Color(1.0, 0.92, 0.75, 0.8), "col1": Color(0.6, 0.85, 0.9, 0.6), "cold": 0.25})
	u.light(c, 200.0, LVUP_CYAN, 0.3)
	motes(c, Vector2.ZERO, Color(LVUP_GOLD.r * 1.5, LVUP_GOLD.g * 1.5, LVUP_GOLD.b * 1.5), 14, 260.0, 0.35, 0.0, 4.0, 2.0, 3.2, 6.0, true)   # 迸开的金色光粒（短、阻力大）
	motes(pos + Vector2(0, -10), Vector2.UP, Color(LVUP_CYAN.r * 1.4, LVUP_CYAN.g * 1.4, LVUP_CYAN.b * 1.4), Bal.vi("fx/levelup_motes", 24), 150.0, 1.1, -70.0, 1.0, 2.0, 0.8, 18.0, true)   # 上升青色光尘
	g.flash = maxf(g.flash, 0.08)
	return true


## ③ 灯火：render/world.update_visuals 每帧调；跌破 30（暗淡）或归零（寂灭）那一刻暗红一压 + 灯里掉余烬；
## 灯火 < 30 时常驻每秒 fx/lamp_low_embers 粒余烬从灯里飘出（ambient_ok 才画）
func watch_lamp(rd: float) -> void:
	if g.state != g.S.PLAY or g.demo_op != "":
		_lamp_prev = g.lamp
		return
	if _lamp_prev >= 0.0 and p2:
		var stage := 0
		if _lamp_prev > 0.0 and g.lamp <= 0.0:
			stage = 2
		elif _lamp_prev >= 30.0 and g.lamp < 30.0:
			stage = 1
		if stage > 0:
			_wv()._flash(Color(0.5, 0.04, 0.14) if stage == 2 else Color(0.45, 0.1, 0.2), 0.55 if stage == 2 else 0.4)
			var lp: Vector2 = g.ppos + Vector2(0, -26)
			motes(lp, Vector2.DOWN, Color(1.8, 0.8, 0.3), Bal.vi("fx/lamp_embers", 10) * (2 if stage == 2 else 1), 70.0, 1.1, 90.0, 0.8, 2.0, 1.3, 6.0, true)
			motes(lp, Vector2.UP, Color(0.35, 0.3, 0.32, 0.7), 6, 40.0, 1.4, -25.0, 0.6, 3.0, 0.5, 4.0)
	_lamp_prev = g.lamp
	if g.lamp < 30.0 and g.lamp > 0.0 and ambient_ok():
		_lamp_ember_acc += rd * _kv("lamp_low_embers", 2.0)
		if _lamp_ember_acc >= 1.0:
			_lamp_ember_acc -= 1.0
			motes(g.ppos + Vector2(0, -26), Vector2.UP, Color(1.6, 0.7, 0.3, 0.8), 1, 35.0, 1.2, -20.0, 0.5, 2.0, 1.0, 5.0, true)
	else:
		_lamp_ember_acc = 0.0


## ④ 精英登场（world 每帧调；按 e.age 画，第一次看到时放一次光尘）：洋红地环扩开 + 8 道竖光 + 柔光
func elite_entrance(e: Dictionary) -> void:
	var key: int = int(e.get("id", 0))
	var age: float = float(e.get("age", 9.0))
	if _sight.has(key):
		age = g.t - float(_sight[key])   # 首次入画起算（elite_entrance_due 登记）
	if age > 0.9 or e.get("dead", false):
		return
	var pos: Vector2 = e.pos
	var r: float = float(e.get("r", 16.0))
	if not _elite_seen.has(key):
		if _elite_seen.size() > 64:
			_elite_seen.clear()
		_elite_seen[key] = true
		glow(pos + Vector2(0, -r), 120.0, Color(1.0, 0.35, 0.8, 0.7), 0.6, 0.4)
		motes(pos, Vector2.UP, Color(1.8, 0.6, 1.4), 12, 120.0, 1.0, -50.0, 1.0, 2.0, 1.0, r)
	var k: float = age / 0.9
	var a: float = 1.0 - k
	var c := Color(1.0, 0.3, 0.72)
	if strip("fx_elite_spawn"):
		# 登场地纹帧条（96×48 × 6，0.9 秒播完）：画成和原程序环最大时一样宽（半径 r×1.1+70），脚下椭圆中心在帧内 (48,24)
		var spec: Array = Game.V6_FRAMES["fx_elite_spawn"]
		var fr: int = mini(int(k * spec[0]), spec[0] - 1)
		var sc: float = (r * 1.1 + 70.0) * 2.0 / 96.0
		spr_rot("fx_elite_spawn", fr, pos + Vector2(0, 2), 0.0, sc, Color(1.6, 1.3, 1.6, 0.9 * minf(1.0, a * 2.0)), Vector2(48, 24))
		return
	var gy: float = _wv().ground_y()
	_wv().tb_ring(pos + Vector2(0, 2), r * 1.1 + 70.0 * k, 3.0, Color(c.r * 1.6, c.g * 1.2, c.b * 1.6, 0.8 * a), 24)
	_wv().tb_ring(pos + Vector2(0, 2), (r * 1.1 + 70.0 * k) * 0.6, 1.5, Color(1.8, 1.4, 1.8, 0.5 * a), 18)
	for q in 8:
		var dv := Vector2.from_angle(q * TAU / 8.0 + 0.4)
		var base: Vector2 = pos + Vector2(dv.x, dv.y * gy) * (r * 1.1 + 70.0 * k)
		_wv().tb_line(base, base + Vector2(0, -(30.0 + 40.0 * a) * a), Color(c.r * 1.8, c.g * 1.4, c.b * 1.8, 0.7 * a), 2.0)


## ⑤ 溟痕光尘（world 溟痕循环里调，无状态：位置 / 相位由 seed 与时间算，不消耗随机数）：每片 1–fx/mire_motes 粒上浮的淡紫光点
func mire_motes(m: Dictionary, budget: int) -> int:
	var n: int = mini(budget, clampi(int(float(m.r) / 22.0), 1, int(_kv("mire_motes", 3.0))))
	if n <= 0:
		return 0
	var a: float = clampf(float(m.life) / 3.0, 0.0, 1.0)
	var sd: float = float(m.get("seed", 0.0))
	var r: float = float(m.r)
	for k in n:
		var period: float = 2.2 + fmod(sd * 0.41 + k * 0.73, 1.0) * 1.4
		var tt: float = g.t + sd * 0.31 + k * 0.57
		var cyc: float = floorf(tt / period)
		var ph: float = (tt - cyc * period) / period
		var h: float = fmod(absf(sin(cyc * 7.3 + k * 3.1 + sd)) * 437.5, 1.0)
		var h2: float = fmod(absf(sin(cyc * 5.9 + k * 1.7 + sd * 1.3)) * 263.7, 1.0)
		var off := Vector2.from_angle(h * TAU) * r * 0.7 * sqrt(h2)
		var p: Vector2 = m.pos + Vector2(off.x, off.y * 0.55 - ph * 34.0 + sin(tt * 2.1) * 3.0)
		var al: float = sin(ph * PI) * 0.55 * a
		var sz: float = 2.0 if k % 2 == 0 else 3.0
		_wv().tb_quad(p, p + Vector2(sz, 0), p + Vector2(sz, sz), p + Vector2(0, sz), Color(1.1, 0.75, 1.6, al))
	return n


## ⑥ 干员晋升 / 入队（progression.pick 调用；原有的蓝环 / 绿环 + 横幅照旧）：金色放射光 + 光柱 + 柔光 + 光尘
func promote_burst(pos: Vector2, elite: bool) -> void:
	if not p2:
		return
	var c := Color(1.0, 0.85, 0.45) if elite else Color(0.6, 0.95, 1.0)
	glow(pos + Vector2(0, -24), 150.0 if elite else 100.0, Color(c.r, c.g, c.b, 0.6), 0.6, 0.4)
	motes(pos + Vector2(0, -10), Vector2.UP, Color(c.r * 2.0, c.g * 1.8, c.b * 1.3), 18 if elite else 10, 130.0, 1.2, -60.0, 1.0, 2.0, 1.2, 18.0)
	if elite:
		g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -20), "life": 0.45, "max": 0.45, "col": c})
		g.fx.append({"kind": "pillar", "pos": pos + Vector2(0, 8), "life": 0.6, "max": 0.6, "col": c})


## ⑦ 拾取（pickups 调用）：油 / 治疗 / 磁铁 / 源石锭 / 宝箱各一小段，颜色跟物品色
func pickup_burst(kind: String, col: Color) -> void:
	if not p2:
		return
	var p: Vector2 = g.ppos + Vector2(0, -22)
	match kind:
		"chest":
			glow(p, 130.0, Color(1.0, 0.85, 0.45, 0.7), 0.6, 0.4)
			g.fx.append({"kind": "rays", "pos": p, "life": 0.4, "max": 0.4, "col": UI.GOLD})
			motes(p, Vector2.UP, Color(2.0, 1.7, 0.9), 16, 150.0, 1.2, -50.0, 1.0, 2.0, 1.2, 14.0)
		"ingot":
			motes(p, Vector2.UP, Color(2.0, 1.8, 1.0), 4, 90.0, 0.7, -40.0, 1.0, 2.0, 0.8, 6.0)
		_:
			glow(p, 90.0, Color(col.r, col.g, col.b, 0.6), 0.5, 0.5)
			g.fx.append({"kind": "ring", "pos": g.ppos, "r": 46.0, "life": 0.3, "max": 0.3, "col": col})
			motes(p, Vector2.UP, Color(col.r * 1.8, col.g * 1.8, col.b * 1.8), 10, 110.0, 1.0, -50.0, 1.0, 2.0, 1.1, 10.0)


## ⑧ 商人（world.update_visuals 每帧调）：出现那一刻一圈暖光 + 光尘；在场时灯笼每秒 fx/merchant_motes 粒暖尘飘起（ambient_ok）
func watch_merchant(rd: float) -> void:
	var here: bool = not g.merchant.is_empty()
	if not here:
		_merchant_seen = false
	var burst := false
	if here and p2:
		# 首次入画才放（docs/54 §7 第 3 条）：刷在屏外时等玩家找到它那一刻；刷在视野内则当帧就放
		if not _merchant_seen and _wv().view_rect(40.0).has_point(g.merchant.pos):
			_merchant_seen = true
			burst = true
	if burst:
		var mp: Vector2 = g.merchant.pos
		glow(mp + Vector2(0, -30), 150.0, Color(1.0, 0.75, 0.45, 0.6), 0.9, 0.3)
		g.fx.append({"kind": "ring", "pos": mp + Vector2(0, 10), "r": 90.0, "life": 0.6, "max": 0.6, "col": Color(1.0, 0.8, 0.5)})
		motes(mp + Vector2(0, -20), Vector2.UP, Color(1.9, 1.5, 0.9), 14, 110.0, 1.3, -40.0, 1.0, 2.0, 1.2, 16.0)
	if here and ambient_ok() and g.merchant.pos.distance_to(g.ppos) < 900.0:
		_merchant_acc += rd * _kv("merchant_motes", 1.5)
		if _merchant_acc >= 1.0:
			_merchant_acc -= 1.0
			motes(g.merchant.pos + merchant_goods() + Vector2(0, -4), Vector2.UP, Color(1.8, 1.3, 0.7, 0.8), 1, 25.0, 1.6, -12.0, 0.4, 2.0, 0.8, 6.0)
	else:
		_merchant_acc = 0.0


## 坎诺特商人身前货物（10-21 重绘去掉提灯）：商店识别暖光（PointLight2D）与暖尘的位置，相对 merchant.pos 的世界偏移；
## 货物在 48 帧里约 (37, 30)，脚底 (24, 45) 画在 pos + (0, 18)；商人随玩家方向镜像（world.gd mflip），货物跟着换边
func merchant_goods() -> Vector2:
	var side: float = -1.0 if g.ppos.x < g.merchant.pos.x else 1.0
	return Vector2(13.0 * side, -15.0) * Game.PX + Vector2(0, 18)


## 加色层：柔光（glow，light 贴图）。draw_add_layer 调用
func draw_glows(ci: CanvasItem) -> void:
	if not p2:
		return
	var lt: Texture2D = g.tex.get("light")
	if lt == null:
		return
	for f in g.fx:
		if f.kind == "aspr":
			# 加色层帧条（docs/54 §6：灯标点燃 / 升级光柱）：按已播时间取帧，末 1/4 淡出
			var tx: Texture2D = g.tex.get(f.name)
			if tx == null:
				continue
			var spec: Array = Game.V6_FRAMES[f.name]
			var fr: int = mini(int((f.max - f.life) * spec[1]), spec[0] - 1)
			var fw: int = tx.get_width() / spec[0]
			var fh: int = tx.get_height()
			var sc: float = f.scale / A.hires_of(tx)
			var an: Vector2 = f.anchor * A.hires_of(tx)
			var fc: Color = f.col
			fc.a *= minf(1.0, f.life / f.max * 4.0)
			ci.draw_set_transform(f.pos.round(), 0.0, Vector2(sc, sc))
			ci.draw_texture_rect_region(tx, Rect2(-an, Vector2(fw, fh)), Rect2(fw * fr, 0, fw, fh), fc)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			continue
		if f.kind != "glow":
			continue
		var a: float = clampf(f.life / f.max, 0.0, 1.0)
		var k: float = 1.0 - a
		var rr: float = f.r * lerpf(f.grow, 1.0, 1.0 - pow(1.0 - k, 2.0))
		var c: Color = f.col
		ci.draw_texture_rect(lt, Rect2(f.pos - Vector2(rr, rr), Vector2(rr * 2.0, rr * 2.0)), false, Color(c.r, c.g, c.b, c.a * a * a))


func _fx_census(name: String, ground: bool) -> void:
	var k: String = name + ("@g" if ground else "")
	_fxc[k] = int(_fxc.get(k, 0)) + 1
	if g.t - _fxc_t >= 30.0:
		_fxc_t = g.t
		print("FXCENSUS ", JSON.stringify(_fxc))


## 特效缩放取整到低分辨率层整数格（docs/138 §10，用户 10-24 定）：s = 每个 1x 美术像素的世界像素数（低分辨率层 1 格 = 2 世界像素）。
## 美术像素 ≥ 0.75 格的取整到最近整数格（至少 1 格），像素宽度均匀、不再一宽一窄；< 0.75 格的不动（画布过大，列重画名单）。
## 只在光学观感低分辨率层开着时生效；按半径拟合（fit）的区域 / 扩散件不走这里（取整会让范围画错）。纯画面
func int_scale(s: float) -> float:
	var fn: int = Engine.get_process_frames()
	if fn != _int_f:
		_int_f = fn
		_int_on = g.optical_on and g.optical != null and g.optical._lo_on and Bal.v("render/fx_int_scale", 1.0) > 0.0
	if not _int_on:
		return s
	var cells: float = absf(s) * 0.5
	if cells < 0.75:
		return s
	return signf(s) * maxf(1.0, roundf(cells)) * 2.0
