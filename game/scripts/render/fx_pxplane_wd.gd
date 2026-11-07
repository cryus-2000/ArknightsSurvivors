## 维什戴尔转平面（docs/274，fx/px_plane = 1）：fx_pxplane.gd 按 id 转来的一节，单独成文件（第五批四人并行，少撞 fx_pxplane.gd）。
## 帧条由 tools/pxplane_bake_wisadel.py 烤（图形 tools/pxplane_wisadel_art.py），键前缀 wd_；炮弹、落点准星、残影标记、续燃引线在这里逐格画
## （算法同 pxplane_wisadel_art.py 的 shell_px() / reticle_px() / bracket_px() / mark_px()，改一边要改另一边）。
## 招牌（每招一个意象）：普攻 = 火星爆（热芯 1–2 拍 → 一圈红 / 亮橙火星带短尾 + 黑碎点，少量红边黑烟 0.4 秒散完；原作黑红）+ 焦痕，余震 = 土尘冲击圈 + 地缝一线红；精一加暗红残影殉爆（好礼）+ 主目标头上残影标记；
## 精二加魂炮（暗红小炮弹 + 暗红殉爆）+ 主爆外圈一道热冲击环。S1 = 处刑火柱（竖直白热柱 → 火团堆成蘑菇帽）+ 落点四角括号；
## S2 = 地毯轰炸（贴地扁爆、一圈矮火团往外滚）+ 放射焦星（精二焦星上留地火）；S3 = 巨炮「黎明」（贴地白热地平线 + 升起的光穹 + 外沿烟环）；
## 连携「天降厚礼」= 她朝天开一炮，死者处各有一发炮弹拖着黑红尾迹从天上砸下 → 落地矮爆 + 三道余震涟漪依次推开。
## 只画：读玩法状态（o.hw.wd 的 shells / quakes / marks），画面专用键只在 wd 里写 pxk（S1 强化炮标记，玩法不读）；不碰玩法与玩法随机数。
## 挂在人身上的件（炮口焰、技能起手星芒）带 fo 跟她走；爆团、焦痕、余震、残影留在原地。
extends RefCounted

const PxU = preload("res://scripts/render/px_util.gd")   # 共用小工具（docs/286 §2）
const Pxp = preload("res://scripts/render/fx_pxplane.gd")
const Bal = preload("res://scripts/core/balance.gd")

const FIRE := [Color("#fff0e4"), Color("#ffa868"), Color("#f04a24"), Color("#c41e18"), Color("#8e1010"), Color("#5c0a0c"), Color("#360608"), Color("#1a0305")]   # 黑红（11-05 用户：对齐原作），偏橙的血红，和敌方预警粉红拉开
const SMOKE := [Color("#0c0607"), Color("#180a0c"), Color("#26100f"), Color("#381a18"), Color("#4e2a28")]
const SOUL := [Color("#14040680"), Color("#2a080cb0"), Color("#3e0c12c0"), Color("#7a141c"), Color("#b82228"), Color("#e8443c"), Color("#ffb0a0")]   # 魂灵之影（11-05 用户去紫）：暗红半透明身 + 红描边，比主炮暗
const IRON := [Color("#141012"), Color("#2a2226"), Color("#463c40"), Color("#6a5e60")]
const SOUL_L := Color(0.8, 0.22, 0.2)      # 魂灵照地光（暗红，比主炮的橙红暗）
const SQ := 0.72
const BOOM_R := [22, 26, 30, 34, 38, 43, 48]
const S1_R := [44, 50, 56, 62]
const S2_R := [44, 48, 54, 60]
const S3_R := [84, 95, 106, 118]
const Q_R := [32, 38, 44, 52, 60, 70, 82, 96, 112, 130, 150]
const SB_R := [18, 22, 26, 30, 34, 38]
const SC_R := [22, 26, 30, 34, 38, 43, 48, 50, 56, 62]   # 焦痕（普攻档 + S1 档）
const HOLD := 0.8          # 焦痕最后一帧停留淡出（秒）
const POP_CAP := 3         # 每拍至多几处被合并的小火团 / 额外弹命中
const BOOM_CAP := 4        # 每拍至多几处主爆团（同屏不碎）
const TIP := Vector2(14, -34)   # 同 wisadel.json blocks.attack.tip（脚底为原点、朝右）
const XSHOT_Y := -18.0          # 同 vis_growth.SHOT_Y（额外弹画在脚底上方）

var _parent: WeakRef
var r:   # Owner holds this helper; the backreference must not retain its cache.
	get:
		return _parent.get_ref()
var g
var _beat := {}
var _mark_runs := {}   # 6 拍 × 有无好礼；只缓存局部像素行，不留敌人引用
var _lines: Array = []   # 续燃引线 / 连锁：{a, b, t0, oid}
var _drops: Array = []   # 连携下坠炮弹：{c, t0, oid}（0.35 秒从 DROP_H 高砸到 c）
var _fogs: Array = []    # 贴地薄雾：{c, r, t0, life, oid}
const SPARK_CAP := 60    # 整队同屏帧条火星上限（11-05 用户怕后期闪眼）
const FOG_MAX := 6
const FOG_A := 0.2       # 薄雾中心不透明度（三层叠到中心 = FOG_A）
const FOG_C := Color(0.3, 0.04, 0.04)
const DROP_T := 0.35     # 同 skill_link l_wisadel 残影 → 炸开的延时
const DROP_H := 240.0

## 原作弹体（11-07 用户「维什戴尔原本的子弹被改成了普通的子弹，按照原作的子弹去做」，fx/wd_shell_v，缺省 1；0 = 转平面第四版的 3×3 黑铁小丸）：
## 照原作 wisdel_attack_01_trail / skill_01_trail（同一套）/ skill_03_trail（弹头、尾迹 ×2）：
## 胶囊弹头（贴图 wisdel_03：粉红弹尖 → 藏蓝弹身 → 白热尾口）+ 红色辉光；主尾迹 Trail_anhong 血红 #ff001a → 藏蓝 #002963 渐隐，
## 外缘 Trail_an 暗红 → 深蓝 → 黑；红（trail_hong #ff7979 → #ff0000）蓝（trail_lan #263679）两股细带绕着尾迹拧；沿途按距离撒红色碎星（lizi #ff2e2e，白 → 红）。
## 原作尾迹 1–1.5 秒，本作炮弹 1500 px/s 只飞 0.08–0.3 秒：尾迹按 0.12 秒飞行长度截、落地后 0.3 秒收尾淡掉（不铺满弹道）。魂炮（魂灵之影）不变。
## 只画：出膛事件记一条画面记录（同 seg_wisadel._h4_fire 的 dur 算法），不读写玩法状态。
const TRC := [Color("#fff4f0"), Color("#ff4a60"), Color("#e8102a"), Color("#a80c26"), Color("#5e0c22"), Color("#2c0e26"), Color("#15224e"), Color("#0b1330")]
const TR_HEADN := [Color("#1c2a5c"), Color("#34488a")]   # 弹身藏蓝（暗 / 受光）
const TR_RIB := [Color("#ff7979"), Color("#263679")]     # 红 / 蓝两股细带（原作 trail_hong / trail_lan 原色；蓝带压暗，免得在暗地面上发紫）
const TR_SPK := [Color("#ffe4e4"), Color("#ff2e2e"), Color("#a80c26")]
const TR_TT := 0.12      # 尾迹长度 = 多少秒的飞行
const TR_FADE := 0.3     # 落地后尾迹收尾
const TR_MAX := 24
var _tr: Array = []      # {fr, to, t0, dur, big, oid}
var _tr_lo := -1


func _init(px) -> void:
	_parent = weakref(px)
	g = px.g


func _beat_n(o, k: String) -> int:
	return PxU.beat_n(_beat, g.t, str(o.id) + k)


## 尺寸档：挑不超过判定 × 1.1 的最大一档（美术像素 = 世界 ÷ 2）；都超过就取最小
static func _pick(arr: Array, r_world: float) -> int:
	var best: int = int(arr[0])
	for x in arr:
		if float(x) * 2.0 <= r_world * 1.1 + 0.01:
			best = int(x)
	return best


func _up(o, k: String, at: Vector2, extra := {}) -> void:
	var it := {"k": "wd_" + k, "t0": g.t, "gp": Pxp._snap(at), "flip": false, "ly": "up", "oid": str(o.id)}
	it.merge(extra, true)
	r._push(it)


## 带火星的帧条（11-05 用户「后期会不会过于闪眼睛」）：整队同屏火星总数封顶 SPARK_CAP；新爆炸放不下全量就换半量 _h / 四分之一 _q 的帧条（热芯照亮）。
## 帧条的火星数在 meta 的 nsp；在场的件按自己的 nsp 计到帧条播完
func _up_sp(o, k: String, at: Vector2, extra := {}) -> void:
	var now: float = g.t
	var live := 0
	for it in r.items:
		if it.has("nsp") and now - float(it.t0) < float(it.spl) and now >= float(it.t0) - 0.5:
			live += int(it.nsp)
	var pick: String = k
	for suf in ["", "_h", "_q"]:
		var m: Dictionary = r._meta("wd_" + k + suf)
		if m.is_empty():
			continue
		pick = k + suf
		if live + int(m.get("nsp", 0)) <= SPARK_CAP:
			break
	var m2: Dictionary = r._meta("wd_" + pick)
	var ex: Dictionary = extra.duplicate()
	ex["nsp"] = int(m2.get("nsp", 0))
	ex["spl"] = float(m2.get("n", 6)) / 15.0
	_up(o, pick, at, ex)


## 贴地薄雾（11-05 用户「体积雾保留一点，不用那种烟雾」）：爆炸后贴地铺开一层很淡的暗红雾，边缘柔、半径 ≤ 判定 × 0.9，life 秒内淡掉；
## 和近处还在的雾合并（刷新、取大），整队同屏至多 FOG_MAX 片，叠加不把地面盖黑
func _fog(o, c: Vector2, rr: float, life: float, delay := 0.0) -> void:
	var now: float = g.t + delay
	var R2: float = rr * 0.9
	for F in _fogs:
		if (F.c as Vector2).distance_to(c) < maxf(float(F.r), R2) * 0.6 and now - float(F.t0) < float(F.life):
			F.t0 = now
			F.r = maxf(float(F.r), R2)
			F.life = maxf(float(F.life), life)
			return
	_fogs.append({"c": c, "r": R2, "t0": now, "life": life, "oid": str(o.id)})
	if _fogs.size() > FOG_MAX:
		_fogs.pop_front()


## 红色体积雾（11-06 用户「维什戴尔的红色体积雾我觉得也还是得加上」，fx/wd_fog_v，缺省 1；0 = 11-05 第四版的淡薄雾原样）：
## 贴地一层偏红的底雾 + 几团慢慢外扩、上浮的雾团（各团大小 / 方向 / 浮高按落点哈希定，不抽随机数），寿命拉长 1.6 倍；手机网页雾团减半（仍画）。
## fx/wd_smoke（缺省 0，给用户对照）：再叠第三版那种往上冒的黑红烟团，画在单位上面（draw_over）
const FOG5_BASE := Color(0.5, 0.07, 0.06)
const FOG5_HI := Color(0.72, 0.13, 0.08)
const FOG5_LO := Color(0.34, 0.05, 0.05)
const SMOKE_C := Color(0.3, 0.08, 0.07)
var _fog_puffs := -1

func _fog_v() -> int:
	return int(Bal.v("fx/wd_fog_v", 1.0))


func _puff_n() -> int:
	if _fog_puffs < 0:
		var cfg = g.get_node_or_null("/root/Cfg")
		_fog_puffs = 3 if cfg != null and cfg.has_method("mobile_web") and cfg.mobile_web() else 5
	return _fog_puffs


static func _fh(x: float) -> float:
	return fposmod(sin(x * 12.9898) * 43758.5453, 1.0)


func _draw_fogs_v5(o, cv) -> void:
	var now: float = g.t
	_fogs = _fogs.filter(func(F): return now - float(F.t0) < float(F.life) * 1.6)
	var np: int = _puff_n()
	for F in _fogs:
		if str(F.oid) != str(o.id) or now < float(F.t0):
			continue
		var life: float = float(F.life) * 1.6
		var age: float = now - float(F.t0)
		var u: float = age / life
		var fin: float = minf(1.0, age / 0.08 + 0.3)
		var R: float = float(F.r)
		var c: Vector2 = F.c
		var sd: float = c.x * 0.37 + c.y * 1.13
		# 底雾：贴地扁圆，三层同心，边柔
		var a0: float = 0.3 * (1.0 - u * u) * fin
		var rr: float = R * (0.8 + 0.3 * sqrt(u))
		cv.draw_set_transform(c, 0.0, Vector2(1.0, SQ))
		for q in 3:
			cv.draw_circle(Vector2.ZERO, rr * (1.0 - 0.28 * q), Color(FOG5_BASE.r, FOG5_BASE.g, FOG5_BASE.b, a0 / 3.0))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 雾团：向外铺开 + 上浮，越往上越淡、越暗
		var ap: float = 0.34 * pow(1.0 - u, 1.4) * fin
		for i in np:
			var h1: float = _fh(sd + float(i) * 3.1)
			var h2: float = _fh(sd + float(i) * 7.7 + 1.0)
			var h3: float = _fh(sd + float(i) * 5.3 + 2.0)
			var ang: float = TAU * (float(i) + 0.6 * h1) / float(np)
			var dist: float = R * (0.2 + 0.45 * h2) * (0.6 + 0.6 * sqrt(u))
			var lift: float = R * (0.25 + 0.35 * h3) * u
			var pc: Vector2 = c + Vector2(cos(ang) * dist, sin(ang) * dist * SQ - lift)
			pc = (pc / 2.0).round() * 2.0
			var pr: float = R * (0.3 + 0.2 * h1) * (0.85 + 0.5 * sqrt(u))
			var k: float = clampf(lift / maxf(R * 0.6, 1.0), 0.0, 1.0)
			var col: Color = FOG5_HI.lerp(FOG5_LO, k)
			cv.draw_set_transform(pc, 0.0, Vector2(1.0, 0.8))
			cv.draw_circle(Vector2.ZERO, pr, Color(col.r, col.g, col.b, ap * 0.45))
			cv.draw_circle(Vector2.ZERO, pr * 0.62, Color(col.r, col.g, col.b, ap * 0.55))
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## fx/wd_smoke = 1：第三版式烟团（暗黑红、往上冒、盖在单位上面），只在爆炸后前 0.7 段画
func _draw_smoke(o, cv) -> void:
	if Bal.v("fx/wd_smoke", 0.0) <= 0.0:
		return
	var now: float = g.t
	for F in _fogs:
		if str(F.oid) != str(o.id) or now < float(F.t0):
			continue
		var life: float = float(F.life) * 1.1
		var age: float = now - float(F.t0)
		if age > life:
			continue
		var u: float = age / life
		var R: float = float(F.r)
		var c: Vector2 = F.c
		var sd: float = c.x * 0.53 + c.y * 0.91 + 9.0
		var a: float = 0.5 * pow(1.0 - u, 1.2) * minf(1.0, age / 0.06)
		for i in 3:
			var h1: float = _fh(sd + float(i) * 4.3)
			var h2: float = _fh(sd + float(i) * 2.9 + 3.0)
			var pc: Vector2 = c + Vector2((h1 - 0.5) * R * 0.7, -R * (0.3 + 0.9 * u) * (0.6 + 0.5 * h2))
			pc = (pc / 2.0).round() * 2.0
			var pr: float = R * (0.22 + 0.14 * h2) * (0.8 + 0.7 * u)
			cv.draw_circle(pc, pr, Color(SMOKE_C.r, SMOKE_C.g, SMOKE_C.b, a * 0.6))
			cv.draw_circle(pc, pr * 0.6, Color(SMOKE_C.r * 1.3, SMOKE_C.g, SMOKE_C.b, a * 0.4))


func _draw_fogs(o, cv) -> void:
	if _fog_v() >= 1 and not (g.opt_old & g.OPT_WDFOG):   # --optmask=67108864 同局轮换：置位画 11-05 淡薄雾（量帧时净差）
		_draw_fogs_v5(o, cv)
		return
	var now: float = g.t
	_fogs = _fogs.filter(func(F): return now - float(F.t0) < float(F.life))
	for F in _fogs:
		if str(F.oid) != str(o.id) or now < float(F.t0):
			continue
		var u: float = (now - float(F.t0)) / float(F.life)
		var a: float = FOG_A * (1.0 - u * u) * minf(1.0, (now - float(F.t0)) / 0.08 + 0.3)
		var rr: float = float(F.r) * (0.75 + 0.25 * sqrt(u))   # 慢慢铺开
		cv.draw_set_transform(F.c, 0.0, Vector2(1.0, SQ))
		for q in 3:   # 三层同心：中心 a、边缘 a / 3（边缘柔）
			cv.draw_circle(Vector2.ZERO, rr * (1.0 - 0.28 * q), Color(FOG_C.r, FOG_C.g, FOG_C.b, a / 3.0))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _gd(o, k: String, at: Vector2, extra := {}) -> void:
	var it := {"k": "wd_" + k, "t0": g.t, "gp": Pxp._snap(at), "flip": false, "ly": "gd", "oid": str(o.id)}
	it.merge(extra, true)
	r._push(it)


## 焦痕：最后一帧再停 HOLD 秒淡掉（life 覆盖帧条寿命）
func _scorch(o, k: String, at: Vector2) -> void:
	var m: Dictionary = r._meta("wd_" + k)
	if m.is_empty():
		return
	_gd(o, k, at, {"hold": true, "life": float(m.n) / 15.0 + HOLD})


func _muzzle(o) -> Vector2:
	return o.pos + Vector2(TIP.x * float(o.face), TIP.y)


# ================================================================ 事件

func ev(o, kind: String, d: Dictionary, t: int, R, p: Dictionary) -> void:
	match kind:
		"wd_fire":   # 出膛：炮口焰（跟她）；魂炮只冒一团暗紫烟（留原地）
			var fr: Vector2 = d.get("from", _muzzle(o))
			var to: Vector2 = d.get("to", fr + Vector2(float(o.face), 0))
			var k: String = str(d.get("kind", ""))
			if k == "soul":
				if _beat_n(o, "smz") < 2:
					_up(o, "smz", fr, {"gy": fr.y + 80.0})
				return
			var dp: Array = Pxp.pick_dir((to - fr).angle())
			var big: bool = k == "giant"
			if _shell_v():
				_tr.append({"fr": fr, "to": to, "t0": g.t, "dur": clampf(fr.distance_to(to) / 1500.0, 0.08, 0.3), "big": big, "oid": str(o.id)})
				if _tr.size() > TR_MAX:
					_tr.pop_front()
			var ex := {"flip": bool(dp[1]), "gy": o.pos.y + 1.0}
			if o.pos != Vector2.INF and fr.distance_to(o.pos) < 80.0:
				ex["fo"] = Pxp._snap(fr) - Pxp._snap(o.pos)
			_up(o, ("mzg_d%d" if big else "mz_d%d") % int(dp[0]), fr, ex)
			if big:
				R._light(o, fr, 110.0, 0.55, 0.1, p.light)
		"wd_boom":
			_boom(o, d, t, R, p)
		"wd_pop":   # 同屏封顶 / 同一轮齐射合并掉的爆炸：一小团火（每拍至多 3）
			if _beat_n(o, "pop") >= POP_CAP:
				return
			_up_sp(o, "pop", d.c, {"gy": (d.c as Vector2).y + 1.0})
		"wd_shade":   # 被炸死 / 带标记倒下的敌人留下残影（暗红半透明人形浮出）
			if _beat_n(o, "shd") >= 3:
				return
			_up(o, "shade", d.pos, {"gy": (d.pos as Vector2).y + 1.0})
		"wd_chain":   # 余烬未冷·续燃：落点吸向残影 —— 一道暗金引线 + 四角括号
			_lines.append({"a": d.a, "b": d.b, "t0": g.t, "oid": str(o.id), "br": true})
			if _lines.size() > 8:
				_lines.pop_front()
		"wd_xhit":   # 后期额外弹命中：暗金小星芒 + 1–2 颗火星
			if _beat_n(o, "xh") >= POP_CAP:
				return
			var at: Vector2 = d.at
			_up(o, "xpop", at, {"gy": at.y + 1.0})
			if _beat_n(o, "xhg") == 0:
				R._grains(o, at + Vector2(0, -12), at.y + 2.0, "streak", 2, {"tier": t})
				R._light(o, at + Vector2(0, -10), 80.0, 0.4, 0.1, p.light)
		"wd_splash":   # 升级卡「扩散」：一小团火（同 pop）
			if _beat_n(o, "pop") >= POP_CAP:
				return
			_up_sp(o, "pop", d.at, {"gy": (d.at as Vector2).y + 1.0})
		"wd_lchain":   # 升级卡「连锁」：1 美术像素暗金引线（3 拍）
			_lines.append({"a": d.a, "b": d.b, "t0": g.t, "oid": str(o.id), "br": false})
			if _lines.size() > 8:
				_lines.pop_front()
		"wd_lgo":   # 连携「天降厚礼」起手：她朝天开一炮（炮口焰朝上，跟她）
			if o.pos == Vector2.INF:
				return
			var mz2: Vector2 = o.pos + Vector2(4.0 * float(o.face), -48.0)
			_up(o, "mzg_d-90", mz2, {"fo": Pxp._snap(mz2) - Pxp._snap(o.pos), "gy": o.pos.y + 1.0})
			R._light(o, mz2, 100.0, 0.55, 0.1, p.light)
		"wd_lghost":   # 连携：死者处一发炮弹从天上砸下来（0.35 秒后落地 = 玩法上残影炸开的时刻），地上先出落点准星
			if _drops.size() >= 10:
				return
			_drops.append({"c": Pxp._snap(d.at), "t0": g.t, "oid": str(o.id)})
		"wd_lblast":   # 连携：落地矮爆 + 三道余震涟漪（半径 60）
			var c: Vector2 = d.at
			if d.get("late", false):   # 补的一发：伤害当下结算，画面等炮弹落地（DROP_T 后）再炸；不挂灯 / 颗粒
				var tl: float = g.t + DROP_T
				_up_sp(o, "lk_up", c, {"gy": c.y + 1.0, "t0": tl, "life": DROP_T + 0.5})
				_fog(o, c, 60.0, 0.6, DROP_T)
				_gd(o, "lk_gd", c, {"t0": tl, "life": DROP_T + 0.7})
				return
			_up_sp(o, "lk_up", c, {"gy": c.y + 1.0})
			_fog(o, c, 60.0, 0.6)
			_gd(o, "lk_gd", c)
			if int(d.get("j", 0)) % 2 == 0:
				R._light(o, c + Vector2(0, -16), 130.0, 0.7, 0.13, p.light)
			R._grains(o, c + Vector2(0, -14), c.y + 2.0, "rock", 2, {"tier": 2, "grain_spd": 1.2})
			R._grains(o, c + Vector2(0, -10), c.y + 2.0, "streak", 3, {"tier": 2, "grain_spd": 1.2})
		"skill":
			var si: int = int(d.get("i", -1))
			if si < 0 or o.pos == Vector2.INF:
				return
			var mz: Vector2 = _muzzle(o)
			_up(o, "glintb" if si == 2 else "glint", mz, {"fo": Pxp._snap(mz) - Pxp._snap(o.pos), "gy": o.pos.y + 2.0})
			R._light(o, mz, 100.0 if si == 2 else 80.0, 0.55, 0.12, p.light)


## 一次爆炸（_h4_boom_visual 转来，已过同屏去重 / 封顶）：按类挑主形
func _boom(o, d: Dictionary, t: int, R, p: Dictionary) -> void:
	var c: Vector2 = d.c
	var rr: float = float(d.get("r", 66.0))
	var k: String = str(d.get("kind", ""))
	var es: Array = d.get("es", [])
	match k:
		"quake":   # 余震：土尘冲击圈 + 地缝；余烬未冷 = 三圈依次推开
			if d.get("rings", false):
				for j in 3:
					var qk: int = _pick(Q_R, rr * [0.6, 0.8, 1.0][j])
					r._push({"k": "wd_q_r%d" % qk, "t0": g.t + 2.0 * j / 15.0, "gp": Pxp._snap(c), "flip": false, "ly": "gd", "oid": str(o.id)})
				R._light(o, c + Vector2(0, -6), minf(160.0, rr), 0.45, 0.12, p.light)
			else:
				_gd(o, "q_r%d" % _pick(Q_R, rr), c)
				if _beat_n(o, "ql") == 0:
					R._light(o, c + Vector2(0, -6), clampf(rr * 0.9, 80.0, 140.0), 0.38, 0.1, p.light)
			if _beat_n(o, "qg") == 0:
				R._grains(o, c + Vector2(0, -4), c.y + 2.0, "rock", 2, {"tier": t})
		"shade", "soul":   # 残影殉爆 / 魂炮落点：暗红内爆 → 火舌（魂炮缩到 0.7）
			if _beat_n(o, "sb") >= 3:
				return
			var sb: int = _pick(SB_R, rr * (0.7 if k == "soul" else 1.0))
			_up(o, "sb_r%d" % sb, c, {"gy": c.y + 1.0})
			if k == "shade" or _beat_n(o, "sbl") == 0:
				R._light(o, c + Vector2(0, -16), clampf(rr * 1.4, 90.0, 140.0), 0.55, 0.12, SOUL_L)
			R._grains(o, c + Vector2(0, -12), c.y + 2.0, "streak", 2 if k == "soul" else 3, {"tier": t})
		"giant":   # 爆裂黎明：照原作 skill_03_hit（fx/wd_dawn_v 1）= 贴地白热芯 + 十字白闪 + 一圈红刺 + 电弧 → 火星；0 = 11-05 自创的地平线 + 光穹；地面冲击环 + 放射裂缝 + 焦痕
			var s3: int = _pick(S3_R, rr)
			_up_sp(o, ("dawn2_r%d" if Bal.v("fx/wd_dawn_v", 1.0) > 0.5 else "dawn_r%d") % s3, c, {"gy": c.y + 2.0})
			_fog(o, c, rr, 0.8)
			_gd(o, "dawng_r%d" % s3, c, {"hold": true, "life": 7.0 / 15.0 + HOLD})
			R._light(o, c + Vector2(0, -30), minf(230.0, rr * 1.15), 0.85, 0.15, p.light)
			R._grains(o, c + Vector2(0, -40), c.y + 2.0, "rock", 6, {"tier": t, "grain_spd": 1.4})
			R._grains(o, c + Vector2(0, -30), c.y + 2.0, "streak", 10, {"tier": t, "grain_spd": 1.4})
		"exec":   # 饱和复仇：贴地扁爆 + 放射焦星（精二焦星上留地火）
			if _beat_n(o, "bm") >= BOOM_CAP:
				return
			var s2: int = _pick(S2_R, rr)
			_up_sp(o, "dome_r%d" % s2, c, {"gy": c.y + 1.0})
			_fog(o, c, rr, 0.6)
			var stk: String = "st_r%d_e%d" % [s2, 2 if t >= 2 else 1]
			_gd(o, stk, c, {"hold": true, "life": float(r._meta("wd_" + stk).get("n", 6)) / 15.0 + HOLD})
			R._light(o, c + Vector2(0, -12), minf(180.0, rr * 1.6), 0.68, 0.12, p.light)
			R._grains(o, c + Vector2(0, -14), c.y + 2.0, "rock", 2, {"tier": t, "grain_spd": 1.2})
			R._grains(o, c + Vector2(0, -10), c.y + 2.0, "streak", 6, {"tier": t, "grain_spd": 1.2})
		_:
			if _beat_n(o, "bm") >= BOOM_CAP:
				return
			if str(d.get("pxk", "")) == "s1":   # 定点清算：处刑火柱
				var s1: int = _pick(S1_R, rr)
				_up_sp(o, "pil_r%d_e%d" % [s1, t], c, {"gy": c.y + 2.0})
				_fog(o, c, rr, 0.7)
				_scorch(o, "sc_r%d" % _pick(SC_R, rr), c)
				R._light(o, c + Vector2(0, -36), minf(190.0, rr * 1.7), 0.75, 0.14, p.light)
				R._grains(o, c + Vector2(0, -30), c.y + 2.0, "rock", 4, {"tier": t, "grain_spd": 1.25})
				R._grains(o, c + Vector2(0, -24), c.y + 2.0, "streak", 8, {"tier": t, "grain_spd": 1.25})
			else:   # 普攻：实心爆团 + 焦痕（精二焦痕外圈一道热冲击环）
				var bk: int = _pick(BOOM_R, rr)
				_up_sp(o, "boom_r%d" % bk, c, {"gy": c.y + 1.0})
				_fog(o, c, rr, 0.55)
				_scorch(o, ("sc2_r%d" if t >= 2 else "sc_r%d") % bk, c)
				R._light(o, c + Vector2(0, -20), clampf(rr * 1.6, 100.0, 150.0), 0.6, 0.12, p.light)
				R._grains(o, c + Vector2(0, -18), c.y + 2.0, "rock", 2, {"tier": t})
				R._grains(o, c + Vector2(0, -14), c.y + 2.0, "streak", 4, {"tier": t})


# ================================================================ 绘制

func _wd(o) -> Dictionary:
	if o.hw.is_empty() or not o.hw.has("wd"):
		return {}
	return o.hw.wd


static func _shell_k(s: Dictionary) -> float:
	return clampf(float(s.t) / maxf(0.001, float(s.dur)), 0.0, 1.0)


## 炮弹画面位置（同 seg_wisadel._h4_shell_at：直线 + 最高拱 18）
static func _shell_at(s: Dictionary, k: float) -> Vector2:
	return (s.from as Vector2).lerp(s.to, k) + Vector2(0, -sin(k * PI) * minf(18.0, (s.from as Vector2).distance_to(s.to) * 0.05))


## 炮弹在地上的投影：出膛点正下方的地面（她的脚底 / 魂灵之影下方）→ 落点
static func _shell_ground(s: Dictionary) -> Vector2:
	var lift: float = 82.0 if str(s.get("kind", "")) == "soul" else 34.0
	return ((s.from as Vector2) + Vector2(0, lift)).lerp(s.to, _shell_k(s))


static func _shell_kind(s: Dictionary) -> String:
	var k: String = str(s.get("kind", ""))
	if k == "giant":
		return "g"
	if k == "soul":
		return "soul"
	if str(s.get("pxk", "")) == "s1" or k == "exec":
		return "s1"
	return "n"


func draw_floor(o) -> void:
	var renderer = r
	var cv = o.cv
	var id: String = str(o.id)
	var px: float = g.PX
	var wd: Dictionary = _wd(o)
	var bt: int = int(floor(g.t * 15.0))
	_draw_fogs(o, cv)
	if not wd.is_empty():
		for s in wd.shells:   # 落点准星 + 弹影
			var k: float = _shell_k(s)
			var c0: Vector2 = Pxp._snap(s.to)
			if str(s.get("kind", "")) != "soul":
				var ra: float = float(s.r) * 0.5
				for q in _reticle(ra, k, bt):
					renderer._px(cv, c0 + q[0] * px, q[1])
				if _shell_kind(s) == "s1":
					for q2 in _bracket(ra * 0.5, bt):
						renderer._px(cv, c0 + q2[0] * px, q2[1])
			var sg: Vector2 = Pxp._snap(_shell_ground(s))
			for dx in [-1, 0, 1]:
				renderer._px(cv, sg + Vector2(dx * px, 0), Color(SMOKE[0].r, SMOKE[0].g, SMOKE[0].b, 0.55))
		for q3 in wd.quakes:   # 余震前兆：落点地缝一圈细暗点，越近越亮
			if float(q3.t) > 0.3:
				continue
			var a: float = 1.0 - float(q3.t) / 0.3
			var rq: float = float(q3.r) * 0.5 * 0.35
			var n: int = maxi(12, int(rq * 2.0))
			for i in n:
				if (i + bt) % 3 == 0:
					continue
				var an: float = TAU * i / n
				renderer._px(cv, Pxp._snap(q3.pos) + Vector2(round(rq * cos(an)), round(rq * sin(an) * SQ)) * px, Color(FIRE[5].r, FIRE[5].g, FIRE[5].b, 0.35 + 0.5 * a))
	var now0: float = g.t
	_drops = _drops.filter(func(D): return now0 - float(D.t0) < DROP_T + 0.05)
	for D in _drops:   # 连携落点准星（半径 30 美术像素 = 爆点 60）+ 弹影
		if str(D.oid) != id:
			continue
		var kd: float = clampf((now0 - float(D.t0)) / DROP_T, 0.0, 1.0)
		for q in _reticle(30.0, kd, bt):
			renderer._px(cv, D.c + q[0] * px, q[1])
		var sw: int = 1 if kd < 0.5 else 2
		for dx in range(-sw, sw + 1):
			renderer._px(cv, D.c + Vector2(dx * px, 0), Color(SMOKE[0].r, SMOKE[0].g, SMOKE[0].b, 0.4 + 0.3 * kd))
	for it in renderer.items_for(id):
		if str(it.ly) != "gd":
			continue
		if it.get("hold", false):
			var m: Dictionary = renderer._meta(str(it.k))
			if m.is_empty():
				continue
			var fi: int = renderer.frame_of(float(it.t0))
			if fi < 0:
				continue
			var age: float = g.t - float(it.t0) - float(m.n) / 15.0
			var al: float = clampf(1.0 - age / HOLD, 0.0, 1.0) if age > 0.0 else 1.0
			renderer._draw_strip(cv, str(it.k), mini(fi, int(m.n) - 1), renderer._gp(it), it.flip, true, Color(1, 1, 1, al))
		else:
			renderer._draw_strip(cv, str(it.k), renderer.frame_of(float(it.t0)), renderer._gp(it), it.flip, true)


## 上层：残影标记（悬在敌人头上，跟着那只）、续燃引线 / 连锁
func draw_over(o) -> void:
	var cv = o.cv
	_draw_smoke(o, cv)
	var px: float = g.PX
	var bt: int = int(floor(g.t * 15.0))
	var wd: Dictionary = _wd(o)
	if not wd.is_empty():
		for key in wd.marks:
			var mk: Dictionary = wd.marks[key]
			var e: Dictionary = mk.e
			if e.dead:
				continue
			if float(mk.t) < 0.6 and (bt / 2) % 2 == 1:   # 快到期：隔两拍闪
				continue
			var c0: Vector2 = Pxp._snap(e.pos + Vector2(0, -float(e.r) - 18.0))
			# 最上一颗火星在 y=-5，带好礼时最右/最下的格子在 (4,4)。
			if r._strip_in_view(cv, Rect2(c0 + Vector2(-3, -5) * px, Vector2(8, 10) * px), true):
				for row in _mark_rows(bt + int(e.id), mk.get("gift", false)):
					var rect: Rect2 = row[0]
					cv.draw_rect(Rect2(c0 + rect.position, rect.size), row[1])
	var now: float = g.t
	_lines = _lines.filter(func(L): return now - float(L.t0) < 0.2)
	for L in _lines:
		if str(L.oid) != str(o.id):
			continue
		var f: int = r.frame_of(float(L.t0))
		if f < 0 or f > 2:
			continue
		var a: Vector2 = L.a
		var b: Vector2 = L.b
		var n: int = maxi(1, int(a.distance_to(b) / px))
		var col: Color = [FIRE[1], FIRE[3], FIRE[5]][f]
		for i in n + 1:
			if f == 2 and i % 2 == 1:
				continue
			r._px(cv, a.lerp(b, float(i) / float(n)), col)
		if f == 0:
			r._glow(b, FIRE[1])
		if L.br:
			for q in _bracket(10.0, bt):
				r._px(cv, Pxp._snap(b) + q[0] * px, q[1])


## 立起层的状态件：炮弹（按地面投影 y 排）
func sort_items(o, out: Array) -> void:
	var vg = o.get("vg")
	if vg is Dictionary and not vg.is_empty():   # 后期额外弹（late_shape / 可见成长）：黑铁小弹 + 两格火尾
		for bu in vg.get("bul", []):
			out.append({"wd": "xshell", "b": bu, "gy": (bu.p as Vector2).y + 1.0})
	for D in _drops:
		if str(D.oid) == str(o.id) and g.t - float(D.t0) < DROP_T:
			out.append({"wd": "drop", "D": D, "gy": (D.c as Vector2).y + 1.0})
	var sv: bool = _shell_v()
	if sv:
		var now: float = g.t
		_tr = _tr.filter(func(T): return now - float(T.t0) < float(T.dur) + TR_TT + TR_FADE)
		var id: String = str(o.id)
		for T in _tr:
			if str(T.oid) == id:
				var kg: float = clampf((now - float(T.t0)) / float(T.dur), 0.0, 1.0)
				out.append({"wd": "trail", "T": T, "gy": ((T.fr as Vector2) + Vector2(0, 34.0)).lerp(T.to, kg).y + 1.0})
	var wd: Dictionary = _wd(o)
	if wd.is_empty():
		return
	for s in wd.shells:
		if sv and str(s.get("kind", "")) != "soul":
			continue
		out.append({"wd": "shell", "s": s, "gy": _shell_ground(s).y + 1.0})


func draw_rt(ci, it: Dictionary) -> void:
	match str(it.wd):
		"trail":
			_draw_trail(ci, it.T)
		"drop":   # 连携下坠炮弹：越落越快（h = H × (1 − u²)），竖直黑红尾迹（同 pxplane_wisadel_art.drop_px）
			var D: Dictionary = it.D
			var u: float = clampf((g.t - float(D.t0)) / DROP_T, 0.0, 1.0)
			var hd3: Vector2 = Pxp._snap((D.c as Vector2) + Vector2(0, -DROP_H * (1.0 - u * u) - 6.0))
			var bt3: int = int(floor(g.t * 15.0))
			for q in _drop(bt3):
				var p3: Vector2 = hd3 + q[0] * g.PX
				r._px(ci, p3, q[1])
				if q[0].y >= 1.0 and q[0].y <= 2.0:
					r._glow(p3, q[1])
		"xshell":
			var bu: Dictionary = it.b
			var px2: float = g.PX
			var dv2: Vector2 = (bu.v as Vector2).normalized()
			if dv2 == Vector2.ZERO:
				dv2 = Vector2.RIGHT
			var nv2 := Vector2(-dv2.y, dv2.x)
			var hd2: Vector2 = Pxp._snap((bu.p as Vector2) + Vector2(0, XSHOT_Y))
			for q in _shell("x", 0):
				r._px(ci, hd2 - dv2 * float(q[0]) * px2 + nv2 * float(q[1]) * px2, q[2])
		"shell":
			var s: Dictionary = it.s
			var px: float = g.PX
			var k: float = _shell_k(s)
			var hd: Vector2 = Pxp._snap(_shell_at(s, k))
			var dv: Vector2 = ((s.to as Vector2) - (s.from as Vector2)).normalized()
			if dv == Vector2.ZERO:
				dv = Vector2.RIGHT
			var nv := Vector2(-dv.y, dv.x)
			var bt: int = int(floor(g.t * 15.0))
			for q in _shell(_shell_kind(s), bt):
				var p: Vector2 = hd - dv * float(q[0]) * px + nv * float(q[1]) * px
				r._px(ci, p, q[2])
				if int(q[0]) <= -1 and absi(int(q[1])) <= 1:
					r._glow(p, q[2])


func _shell_v() -> bool:
	return Bal.v("fx/wd_shell_v", 1.0) > 0.5


## 手机网页：碎星减半、细带隔格画（仍画）
func _trail_lo() -> bool:
	if _tr_lo < 0:
		var cfg = g.get_node_or_null("/root/Cfg")
		_tr_lo = 1 if cfg != null and cfg.has_method("mobile_web") and cfg.mobile_web() else 0
	return _tr_lo == 1


static func _tr_at(a: Vector2, b: Vector2, arc: float, k: float) -> Vector2:
	return a.lerp(b, k) + Vector2(0, -sin(k * PI) * arc)


static func _tr_col(u: float) -> Color:
	if u < 0.06:
		return TRC[0]
	if u < 0.12:
		return TRC[1]
	if u < 0.3:
		return TRC[2]
	if u < 0.46:
		return TRC[3]
	if u < 0.6:
		return TRC[4]
	if u < 0.72:
		return TRC[5]
	if u < 0.86:
		return TRC[6]
	return TRC[7]


## 原作弹体（见 TRC 上的说明）：尾迹按主轴逐格走（每格一个竖 / 横条，宽度随离弹头远近收窄）→ 红蓝细带 → 碎星 → 弹头
func _draw_trail(ci, T: Dictionary) -> void:
	var px: float = g.PX
	var now: float = g.t
	var age: float = now - float(T.t0)
	var dur: float = float(T.dur)
	var big: bool = bool(T.big)
	var life: float = 0.35 if big else 0.25
	if age > dur + life:   # 弹头已落地、尾带已收完，最晚生成的碎星也已到期。
		return
	var renderer = r
	var lo: bool = _trail_lo()
	var kh: float = clampf(age / dur, 0.0, 1.0)
	var kt: float = clampf((age - TR_TT) / dur, 0.0, 1.0)
	var fade: float = 1.0 if age <= dur else clampf(1.0 - (age - dur) / TR_FADE, 0.0, 1.0)
	var bt: int = int(floor(now * 15.0))
	var start: Vector2 = T.fr
	var end: Vector2 = T.to
	var length := start.distance_to(end)
	var arc := minf(18.0, length * 0.05)
	var dv: Vector2 = (end - start).normalized()
	if dv == Vector2.ZERO:
		dv = Vector2.RIGHT
	var nv := Vector2(-dv.y, dv.x)
	var horiz: bool = absf(dv.x) >= absf(dv.y)
	var total: float = length / px   # 弹道全长（美术像素）
	var wmax: float = 5.0 if big else 3.0
	if kh > kt and fade > 0.0:
		var ph: Vector2 = _tr_at(start, end, arc, kh)
		var pt: Vector2 = _tr_at(start, end, arc, kt)
		var n: int = maxi(1, int(ceil(ph.distance_to(pt) / px)))
		var lam: float = 20.0 if big else 14.0
		var amp: float = 4.0 if big else 2.0
		for i in n + 1:
			var u: float = float(i) / float(n)
			var kk: float = lerpf(kh, kt, u)
			var p: Vector2 = Pxp._snap(_tr_at(start, end, arc, kk))
			var w: int = maxi(1, int(round(lerpf(wmax, 1.0, u))))
			var al: float = fade * (1.0 if u < 0.35 else lerpf(1.0, 0.0, (u - 0.35) / 0.65))
			var c: Color = _tr_col(u)
			if u < 0.4 and w >= 2:   # 外缘 Trail_an：暗一阶的深蓝边（只在靠弹头的一段）
				_span(ci, p, w + 2, horiz, Color(TRC[7].r, TRC[7].g, TRC[7].b, 0.7 * al))
			_span(ci, p, w, horiz, Color(c.r, c.g, c.b, al))
			if u > 0.04 and u < 0.55 and not (lo and i % 2 == 1):   # 红蓝两股细带绕着拧（相位跟着弹道走、按拍转）
				var dist: float = kk * total
				var phs: float = dist / lam * TAU - float(bt) * 1.3
				var off: float = amp * (1.0 - u * 0.5) * sin(phs)
				var front: bool = cos(phs) > 0.0
				var hw: float = float(w) * 0.5
				if front or absf(off) > hw:
					renderer._px(ci, p + nv * round(off) * px, Color(TR_RIB[0].r, TR_RIB[0].g, TR_RIB[0].b, al))
				if (not front) or absf(off) > hw:
					renderer._px(ci, p - nv * round(off) * px, Color(TR_RIB[1].r, TR_RIB[1].g, TR_RIB[1].b, al))
	# 碎星（lizi）：弹道上每隔 sp 格生一颗，按飞到那里的时刻起算寿命；位置 / 漂移按序号哈希定
	var sp: float = (6.0 if big else 9.0) * (2.0 if lo else 1.0)
	var nj: int = int(total / sp)
	for j in nj:
		var kj: float = (float(j) + 0.5) * sp / maxf(1.0, total)
		if kj > kh:
			break
		var aj: float = age - kj * dur
		if aj < 0.0 or aj > life:
			continue
		var h1: float = _fh(float(j) * 1.37 + float(T.t0) * 3.1)
		var h2: float = _fh(float(j) * 2.71 + float(T.t0) * 1.7)
		var uj: float = aj / life
		var sc: Color = TR_SPK[0] if uj < 0.3 else (TR_SPK[1] if uj < 0.75 else TR_SPK[2])
		var q: Vector2 = _tr_at(start, end, arc, kj) + nv * ((h1 * 2.0 - 1.0) * (5.0 if big else 3.0) + (h1 - 0.5) * aj * 40.0) * px * 0.5 + Vector2((h2 - 0.5) * aj * 30.0, aj * 20.0) * px * 0.5
		var qs: Vector2 = Pxp._snap(q)
		renderer._px(ci, qs, sc)
		if big and h2 > 0.6 and uj < 0.5:   # 巨炮大颗：十字星
			for dd in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				renderer._px(ci, qs + dd * px, Color(TR_SPK[1].r, TR_SPK[1].g, TR_SPK[1].b, 0.8))
	# 弹头：胶囊（前圆后平），粉红弹尖 → 藏蓝弹身（上沿受光）→ 白热尾口；红色辉光
	if age < dur:
		var hd: Vector2 = Pxp._snap(_tr_at(start, end, arc, kh))
		var hl: int = 5 if big else 3
		var hw2: int = 2 if big else 1
		for qq in range(-hl, hl + 1):
			for ww in range(-hw2, hw2 + 1):
				var e: float = pow(float(qq) / (float(hl) + 0.5), 2.0) + pow(float(ww) / (float(hw2) + 0.5), 2.0)
				if qq < 0 and e > 1.0:
					continue   # 前端圆头；后端平
				var hc: Color
				if qq <= -hl + 1:
					hc = TRC[0] if (qq == -hl + 1 and ww == -hw2 + (1 if big else 0)) else TRC[1]
				elif qq >= hl - (1 if big else 0):
					hc = TRC[0]
				else:
					hc = TR_HEADN[1] if ww == -hw2 else TR_HEADN[0]
				renderer._px(ci, hd - dv * float(qq) * px + nv * float(ww) * px, hc)
		renderer._glow(hd + dv * float(hl) * px, Color(1.0, 0.16, 0.22))
		renderer._glow(hd - dv * float(hl) * px, Color(1.0, 0.5, 0.5))


## 一格宽的横 / 竖条（沿弹道主轴的法向铺 w 格），一次 draw_rect
func _span(ci, p: Vector2, w: int, horiz: bool, c: Color) -> void:
	var px: float = g.PX
	var h: float = float(w) * px
	var o0: float = float(w / 2) * px
	if horiz:
		ci.draw_rect(Rect2(p + Vector2(0, -o0), Vector2(px, h)), c)
	else:
		ci.draw_rect(Rect2(p + Vector2(-o0, 0), Vector2(h, px)), c)


# ---------------------------------------------------------------- 运行时件的像素（同 pxplane_wisadel_art.py）

## 炮弹：[沿向 q（负 = 弹头前端），法向 w，颜色]
func _shell(kind: String, beat: int) -> Array:
	var out: Array = []
	var head := 1
	var tail: Array
	var body: Array = IRON
	match kind:
		"g":
			head = 3
			tail = [FIRE[1], FIRE[2], FIRE[2], FIRE[3], FIRE[3], FIRE[4], FIRE[5], SMOKE[3], SMOKE[2]]
		"s1":
			head = 2
			tail = [FIRE[2], FIRE[2], FIRE[3], FIRE[4], FIRE[5], SMOKE[3]]
		"soul":
			tail = [SOUL[4], SOUL[3], SOUL[2]]
			body = [SOUL[1], SOUL[2], SOUL[3], SOUL[5]]
		"x":
			tail = [FIRE[3], FIRE[5]]
		_:
			tail = [FIRE[2], FIRE[3], FIRE[5], SMOKE[3]]
	var lim: int = head + (1 if head >= 2 else 0)
	for q in range(-head, head + 1):
		for w in range(-head, head + 1):
			if absi(q) + absi(w) > lim:
				continue
			var c: Color = body[1] if w < 0 else body[0]
			if q == -head:
				c = FIRE[1] if kind != "soul" else SOUL[6]
			elif q == -head + 1 and w <= 0:
				c = body[3] if kind != "soul" else SOUL[5]
			out.append([q, w, c])
	for i in tail.size():
		var q2: int = head + 1 + i
		var wob := 0
		if kind != "x" and i > 1:
			var m: int = (beat + i) % 4
			wob = 1 if m == 0 else (-1 if m == 2 else 0)
		out.append([q2, wob, tail[i]])
		if kind == "g" and i < 5:
			var hc: Color = FIRE[3] if i < 3 else FIRE[4]
			out.append([q2, 1, hc])
			out.append([q2, -1, hc])
		elif kind == "s1" and i < 3:
			out.append([q2, 1 if i % 2 == 0 else -1, FIRE[3]])
	return out


## 落点准星：[美术像素偏移, 颜色]
func _reticle(ra: float, k: float, beat: int) -> Array:
	var out: Array = []
	var rr: float = ra * (1.1 - 0.1 * k)
	var n: int = maxi(24, int(rr * 6.3 / 2.0))
	var col: Color = FIRE[4] if k < 0.6 else FIRE[3]
	for i in n:
		if (i + beat) % 4 == 3:
			continue
		var a: float = TAU * i / n
		out.append([Vector2(round(rr * cos(a)), round(rr * sin(a) * SQ)), col])
	for j in 4:
		var a2: float = j * PI / 2.0
		for s in 3:
			out.append([Vector2(round((rr - 2 - s) * cos(a2)), round((rr - 2 - s) * sin(a2) * SQ)), FIRE[2] if s == 0 else col])
	return out


## S1 落点 / 续燃吸附点：四角括号，随拍往里收一格
func _bracket(ra: float, beat: int) -> Array:
	var out: Array = []
	var rr: float = ra - float(beat % 3)
	for k in 4:
		var a: float = PI / 4.0 + k * PI / 2.0
		var cx: float = rr * cos(a)
		var cy: float = rr * sin(a) * SQ
		var sx: float = 1.0 if cos(a) > 0.0 else -1.0
		var sy: float = 1.0 if sin(a) > 0.0 else -1.0
		for s in 4:
			out.append([Vector2(round(cx - sx * s), round(cy)), FIRE[2] if s == 0 else FIRE[3]])
			out.append([Vector2(round(cx), round(cy - sy * s)), FIRE[3]])
	return out


## 残影标记：暗红小魂火（5 宽 7 高）+ 两点亮红眼；好礼 = 脚边一粒橙红
func _mark_rows(beat: int, gift: bool) -> Array:
	var key := beat % 6 + (6 if gift else 0)
	if beat >= 0 and _mark_runs.has(key):
		return _mark_runs[key]
	var rows := []
	var px: float = g.PX
	for cell in _mark(beat, gift):
		var pos: Vector2 = cell[0] * px
		if not rows.is_empty():
			var last: Array = rows.back()
			var rect: Rect2 = last[0]
			if last[1] == cell[1] and rect.position.y == pos.y and rect.end.x == pos.x:
				last[0] = Rect2(rect.position, rect.size + Vector2(px, 0))
				continue
		rows.append([Rect2(pos, Vector2(px, px)), cell[1]])
	if beat >= 0:
		_mark_runs[key] = rows
	return rows


func _mark(beat: int, gift: bool) -> Array:
	var out: Array = []
	var bob: int = 1 if (beat / 3) % 2 == 1 else 0
	for row in [[-3, 0], [-2, 1], [-1, 2], [0, 2], [1, 2], [2, 1], [3, 1]]:
		var y: int = int(row[0])
		var hw: int = int(row[1])
		for x in range(-hw, hw + 1):
			var c: Color = SOUL[3] if absi(x) == hw else SOUL[1]
			if y <= -2:
				c = SOUL[4] if (beat + x) % 2 == 0 else SOUL[3]
			out.append([Vector2(x, y - bob), c])
	out.append([Vector2(-1, -bob), SOUL[6]])
	out.append([Vector2(1, -bob), SOUL[6]])
	out.append([Vector2((beat / 2) % 3 - 1, -4 - bob), SOUL[5]])
	if gift:
		out.append([Vector2(3, 3 - bob), FIRE[2]])
		out.append([Vector2(4, 3 - bob), FIRE[4]])
		out.append([Vector2(3, 4 - bob), FIRE[4]])
	return out


## 连携下坠炮弹：[美术像素偏移（原点 = 弹头中心）, 颜色]
func _drop(beat: int) -> Array:
	var out: Array = []
	for y in range(-1, 2):
		for x in range(-1, 2):
			out.append([Vector2(x, y), IRON[1] if x < 0 else IRON[0]])
	out.append([Vector2(0, 2), FIRE[0]])
	out.append([Vector2(-1, 1), FIRE[2]])
	out.append([Vector2(1, 1), FIRE[3]])
	var tail: Array = [FIRE[1], FIRE[2], FIRE[2], FIRE[2], FIRE[3], FIRE[3], FIRE[3], FIRE[4], FIRE[4], FIRE[4], FIRE[5], FIRE[5], FIRE[5], FIRE[6], FIRE[6], SMOKE[3], SMOKE[3], SMOKE[2], SMOKE[2], SMOKE[2], SMOKE[1], SMOKE[1]]
	for i in tail.size():
		var y2: int = -2 - i
		var wob := 0
		if i > 8:
			var m: int = (beat + i) % 4
			wob = 1 if m == 0 else (-1 if m == 2 else 0)
		out.append([Vector2(wob, y2), tail[i]])
		if i < 10:
			out.append([Vector2(-1, y2), FIRE[4] if i < 3 else FIRE[5]])
			out.append([Vector2(1, y2), FIRE[4] if i < 3 else FIRE[5]])
	return out
