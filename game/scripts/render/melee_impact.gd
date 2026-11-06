## 近战打击感包（docs/246 §11，11-05 用户实机「现在近战打击感比较弱」）：开关 fx/melee_impact（缺省 0 = 关），先给斯卡蒂、星熊，11-05 加推进之王（docs/264）。
## 只改画面，不碰玩法与随机数（同种子 TRACE 开关逐行一致）：
##   ① 命中顿帧：走 vfx.stop 总闸（平衡 / 批跑局不消耗顿帧）；队长全量、队友按 fx/melee_impact_mate 比例；轻击 / 重击两档；
##   ② 重击轻震镜头：g.ult.shake（按真实时间、减少动态效果时为 0），用户同意的 3px / 0.12s 量级；
##   ③ 被打的怪闪本人色（取代白闪，经 fx_recipe.react_col 回落到这里）+ 画面上被推开一小段再弹回（world._eoff 叠加，判定位置不动）；
##   ④ 斩痕 / 照地光提亮（fx_pxplane 读 lit_k()）。命中音照旧（vfx._tier_fx 在接管判断之前就播）。
## 重击 = 技能来源（tags 带 skill）或下面 HEAVY 里的招式名。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const IDS := {"skadi": Color(0.55, 0.78, 1.0), "hoshiguma": Color(1.0, 0.78, 0.42), "siege": Color(1.0, 0.75, 0.3), "mizuki": Color(0.44, 0.91, 1.0), "gladiia": Color(0.62, 0.72, 1.0), "ulpianus": Color(0.62, 0.69, 0.94), "specter_unchained": Color(0.6, 0.85, 1.0), "lappland": Color(0.8, 0.76, 1.0), "irene": Color(0.82, 0.88, 1.0), "saria": Color(1.0, 0.9, 0.62)}   # 推进之王（docs/264）：锤击 / 跃空锤落地；水月（docs/261）：水母荧光青
const HEAVY := {"迅捷打击·γ型": true, "跃浪击": true, "破浪下劈": true, "反手斩": false, "大洋裂断": true, "冲撞": true, "狼之舞": true, "断喝": true, "噤声": true}
## 不走打击感包的招：歌蕾蒂娅 S3 每 0.75 秒一跳、反震（持续 / 被动，顿帧震屏会一直抖）
const SKIP := {"碎漩狂舞": true, "反震": true}
const FLASH_T := 0.07


static func on(g) -> bool:
	return g != null and not g.headless_batch and Bal.v("fx/melee_impact", 0.0) > 0.0


## 斩痕 / 照地光的提亮倍数（开关关时 1）
static func lit_k(g) -> float:
	return Bal.v("fx/melee_impact_lit", 1.35) if on(g) else 1.0


## ob_core.exec_shape 判定结算后调（只画）：o 出手的干员，src 招式名，tags，hits 被打中的敌人
static func hit(o, src: String, tags: Array, hits: Array) -> void:
	if not hits.is_empty() and has_op(str(o.id)):   # 按干员调的卡肉（fx/melee_impact_op/<干员>，德克萨斯 11-05）
		meat(o, src, hits)
		return
	if hits.is_empty() or not IDS.has(str(o.id)) or SKIP.has(src):
		return
	if str(o.id) == "ulpianus" and src in ["撼地", "定点爆破", "锁链回旋"]:   # 乌尔比安（docs/266）：锚击的附带冲击不再顿一次
		return
	var g = o.g
	if not on(g):
		return
	var heavy: bool = "skill" in tags or bool(HEAVY.get(src, false))
	var col: Color = IDS[str(o.id)]
	var px: float = Bal.v("fx/melee_impact_push_heavy", 4.7) if heavy else Bal.v("fx/melee_impact_push", 2.7)
	# ① 顿帧
	var sec: float = Bal.v("fx/melee_impact_stop_heavy", 0.0375) if heavy else Bal.v("fx/melee_impact_stop", 0.0225)
	var frozen := 0.0
	if hfo(o, "layer"):   # 顿帧分层（docs/291 §7.1）：队长普攻局部停、重击全局停；队友不停
		if o.is_leader and heavy and g.vfx != null:
			g.vfx.stop(sec, "melee_impact")
		elif o.is_leader:
			frozen = _freeze(o, hits, Bal.v("fx/hf_local_ms", 45.0) / 1000.0, Bal.v("fx/hf_local_cap_ms", 150.0) / 1000.0, int(Bal.v("fx/hf_local_targets", 4.0)), px)
	else:
		if not o.is_leader:
			sec *= Bal.v("fx/melee_impact_mate", 0.6)
		if g.vfx != null:
			g.vfx.stop(sec, "melee_impact")
	# ② 重击轻震
	if heavy and hfo(o, "cam"):
		_cam(o, hits)   # 定向推镜 + 手柄短震（docs/291 §7.3），只给队长
	elif heavy and g.ult != null:
		g.ult.shake(Bal.v("fx/melee_impact_shake_px", 3.0), Bal.v("fx/melee_impact_shake_t", 0.12))
	if hfo(o, "flesh"):
		_flesh(o, hits.size(), heavy)
	# ③ 闪色 + 画面击退（每只记在敌人字典的画面专用键 mi_*，玩法不读）；局部停住的已在 _freeze 里写好（先白闪、停完再推）
	for e in ([] if frozen > 0.0 else hits):
		if not (e is Dictionary) or e.get("dead", false):
			continue
		var d: Vector2 = (e.pos - o.pos)
		e["mi_at"] = g.t
		e["mi_dir"] = d.normalized() if d.length() > 0.5 else Vector2.RIGHT
		e["mi_px"] = px * (0.4 if e.get("boss", false) else (0.7 if e.get("elite", false) else 1.0))
		e["mi_col"] = col
	_evo_hit(o, hits, 0.0, heavy, col)   # 打击感进化（docs/291）：全局顿帧停 g.t，自然停住


## world._eoff 叠加：推开 fx/melee_impact_push_in 秒、fx/melee_impact_push_back 秒弹回（画面位移，按美术像素取整）
## 11-05 用户「打击感现在又有点太钝了」：推开 0.04 → 0.027、弹回 0.12 → 0.08（时长约缩 1/3），位移 push 4 → 2.7 / 7 → 4.7
static func off(g, e: Dictionary) -> Vector2:
	if not e.has("mi_at") or not on(g):
		return Vector2.ZERO
	var age: float = g.t - float(e.mi_at)
	var ti: float = maxf(0.001, Bal.v("fx/melee_impact_push_in", 0.027))
	var tb: float = maxf(0.001, Bal.v("fx/melee_impact_push_back", 0.08))
	if age < 0.0 or age > ti + tb:
		return Vector2.ZERO
	var k: float = age / ti if age < ti else 1.0 - (age - ti) / tb
	return ((e.mi_dir as Vector2) * float(e.mi_px) * k / 2.0).round() * 2.0


## fx_recipe.react_col 回落到这里：a < 0 = 不接管（照旧白闪），a > 0 = 闪本人色
static func col(g, e: Dictionary) -> Color:
	if not e.has("mi_at") or not on(g) or e.get("boss", false):
		return Color(0, 0, 0, -1)
	var age: float = g.t - float(e.mi_at)
	if age < 0.0 or age > FLASH_T:
		return Color(0, 0, 0, -1)
	var c: Color = e.mi_col
	return Color(c.r, c.g, c.b, 0.85)


# ================================================================ 卡肉（局部顿帧，11-05 用户用德克萨斯打「没有卡肉感」）
## 旋钮 fx/melee_impact_op/<干员>/…（balance.json，按干员调，没写的干员走上面的通用包）：
##   hitstop_ms/<招式名>  命中停多少毫秒（0 = 这招不卡）；cap_ms 每 1 游戏秒顿帧总量上限（后期怪多不一直卡）；
##   targets 一次最多冻结几只（离施放者最近的）；push / push_heavy 推开距离（世界像素；≥ heavy_ms 的招算重）；snd_db 斩肉声音量。
## 局部：只停施放者本体那一帧（character.vis_hold_until，draw_body 只画）、被打的怪的选帧（fx_recipe.reacts，只画）和斩痕帧条多停一拍（fx_pxplane），
## 世界、g.t、玩法一概不停，所以同种子 TRACE 开关一致。被打的怪先白闪（停住期间），停完再往后推开、弹回。
static func has_op(oid: String) -> bool:
	return not Bal.sec("fx/melee_impact_op/" + oid).is_empty()


static func opk(oid: String, key: String, d: float) -> float:
	return Bal.v("fx/melee_impact_op/%s/%s" % [oid, key], d)


static func meat(o, src: String, hits: Array) -> void:
	var g = o.g
	if hits.is_empty() or not on(g):
		return
	var oid: String = str(o.id)
	var ms: float = opk(oid, "hitstop_ms/" + src, 0.0)
	if ms <= 0.0:
		return
	var heavy: bool = ms >= opk(oid, "heavy_ms", 50.0)
	var sec: float = ms / 1000.0 * (1.0 if o.is_leader else Bal.v("fx/melee_impact_mate", 0.6))
	if hfo(o, "layer") and not o.is_leader:
		sec = 0.0   # 顿帧分层（docs/291 §7.1）：队友不顿帧
	var px: float = opk(oid, "push_heavy" if heavy else "push", 7.0 if heavy else 4.0)
	var got: float = _freeze(o, hits, sec, opk(oid, "cap_ms", 150.0) / 1000.0, int(opk(oid, "targets", 4.0)), px)
	_evo_hit(o, hits, got, heavy, EVO_COL.get(oid, IDS.get(oid, Color(1.0, 0.8, 0.5))))   # 打击感进化（docs/291）
	if heavy and hfo(o, "cam"):
		_cam(o, hits)
	if hfo(o, "flesh"):
		_flesh(o, hits.size(), heavy)
		return
	if got <= 0.0:
		return
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
	if sfx != null:
		var nm: String = "op_%s_flesh_%d" % [oid, 1 + int(g.t * 13.0) % 2]
		sfx.ensure([nm])
		sfx.play(nm, opk(oid, "snd_db", -5.0) + (0.0 if heavy else -3.0), 1.0, 0.05)


## 局部停帧（只画，从 meat 抽出来给通用包共用）：施放者本体停 sec 秒、离得最近的 nt 只被打的怪冻住并白闪，停完再推开 px；
## 同一游戏秒里总量封顶 cap 秒。返回实际停了多少秒（0 = 这下没停，被打的怪照样白闪 + 推开）
static func _freeze(o, hits: Array, sec: float, cap: float, nt: int, px: float) -> float:
	var g = o.g
	var q: Array = o.get_meta("mi_q", [])
	q = q.filter(func(x): return g.t - float(x[0]) < 1.0 and g.t >= float(x[0]))
	var used := 0.0
	for x in q:
		used += float(x[1])
	sec = minf(sec, cap - used)   # 同一秒里顿帧总量封顶
	var hold: bool = sec >= 0.015
	if hold:
		q.append([g.t, sec])
		o.vis_hold_until = g.t + sec
		o.vis_hold_st = {}
	o.set_meta("mi_q", q)
	var lst: Array = hits.filter(func(e): return e is Dictionary and not e.get("dead", false))
	lst.sort_custom(func(a, b): return a.pos.distance_squared_to(o.pos) < b.pos.distance_squared_to(o.pos))
	var R = load("res://scripts/render/fx_recipe.gd").of(g)
	for i in lst.size():
		var e: Dictionary = lst[i]
		var frz: bool = hold and i < nt and not e.get("boss", false)
		var hs: float = sec if frz else 0.0
		R.reacts[e.id] = [g.t, Color(1, 1, 1), g.t + hs if frz else -1.0, g.t, hs + 0.04]   # 先白闪（停住期间）
		var d: Vector2 = (e.pos - o.pos)
		e["mi_at"] = g.t + hs   # 停完再推开
		e["mi_dir"] = d.normalized() if d.length() > 0.5 else Vector2.RIGHT
		e["mi_px"] = px * (0.4 if e.get("boss", false) else (0.7 if e.get("elite", false) else 1.0))
		e["mi_col"] = Color(1, 1, 1)
	if hold and g.has_meta("fx_pxplane"):
		g.get_meta("fx_pxplane").stuck(o, sec)   # 斩痕命中那一拍多停一拍
	return sec if hold else 0.0


# ================================================================ 打击感取舍四条（docs/291 §7，11-07 用户「按你的取舍做」）
## 每条一个开关（缺省 0），按干员 fx/hf_op/<干员> 试点（德克萨斯、推进之王）；Boss 击杀慢放不分干员。
##   layer  顿帧分层：队长普攻改局部停（hf_local_ms，世界不停）、重击仍全局停；队友不顿帧
##   flesh  肉感层：一下只播一次 op_<干员>_flesh_1/2，按这一下命中数加 0–3 dB（每多 2 只 +hf_flesh_db_per）、音高略降；队友再 −4 dB
##   cam    重击定向推镜：沿出手方向推 hf_push_px 美术像素、hf_push_t 秒阶梯回位，代替随机轻震；队长重击加手柄短震
##   boss_slow  中期 Boss 击杀慢放（见 boss_slow）
static func hfo(o, key: String) -> bool:
	return Bal.v("fx/hf_" + key, 0.0) > 0.0 and Bal.v("fx/hf_op/" + str(o.id), 0.0) > 0.0


static func _flesh(o, n: int, heavy: bool) -> void:
	var g = o.g
	var oid: String = str(o.id)
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
	if sfx == null or not ResourceLoader.exists("res://audio/sfx/op_%s_flesh_1.wav" % oid):
		return
	var nm: String = "op_%s_flesh_%d" % [oid, 1 + int(g.t * 13.0) % 2]
	sfx.ensure([nm])
	var add: float = clampf(floor(float(n) / 2.0) * Bal.v("fx/hf_flesh_db_per", 1.0), 0.0, 3.0)   # 1 只 0、2–3 只 +1、4–5 只 +2、6 只以上 +3 dB
	var db: float = opk(oid, "snd_db", Bal.v("fx/hf_flesh_db", -5.0)) + (0.0 if heavy else -3.0) + add + (0.0 if o.is_leader else -4.0)
	sfx.play(nm, db, 1.0 - 0.02 * add, 0.05)


static func _cam(o, hits: Array) -> void:
	var g = o.g
	var cfg = g.get_node_or_null("/root/Cfg")   # 不直接写 Cfg：核心契约测试（-s 脚本模式）没有自动加载
	if not o.is_leader or g.world == null or (cfg != null and cfg.reduce_motion):
		return
	var best = null
	var bd := INF
	for e in hits:
		if e is Dictionary:
			var dd: float = e.pos.distance_squared_to(o.pos)
			if dd < bd:
				bd = dd
				best = e
	if best == null:
		return
	g.world.kick(o.pos - best.pos, int(Bal.v("fx/hf_push_px", 2.0)), Bal.v("fx/hf_push_t", 0.12))   # kick 往 -to_target 推：传反向 = 往出手方向推
	if Bal.v("fx/hf_rumble", 1.0) > 0.0:
		var pad = g.get_node_or_null("/root/Pad")   # 同上：不直接写自动加载 Pad
		if pad != null:
			pad.rumble(Bal.v("fx/hf_rumble_weak", 0.2), Bal.v("fx/hf_rumble_strong", 0.35), Bal.v("fx/hf_rumble_t", 0.08))


## 中期 Boss 击杀慢放（docs/291 §7.4）：combat.kill 在原来的 0.12 秒停顿之后调；最终 Boss 已有 victory_flow 约 2 秒慢放，不叠。
## 走 time_dilation 的 fx 类（同终结技冲击慢放）：只在玩家局 / --realtime / --playclock 缩游戏步长，机器人批跑不缩。
static func boss_kill(g, e: Dictionary) -> void:
	if Bal.v("fx/hf_boss_slow", 0.0) <= 0.0 or not e.get("boss", false) or e.get("part", false) or g.spawner == null or g.spawner.is_final_boss_type(str(e.get("type", ""))):
		return
	g.set_meta("hf_boss_rt", _um_now())


## 倍率（真实时间轴）：顿帧 hf_boss_wait 秒后 × hf_boss_lo 保持 hf_boss_t 秒，再按终结技的 ult/imp_ease 先慢后快回 1
static func boss_slow(g) -> float:
	if not g.has_meta("hf_boss_rt"):
		return 1.0
	var t: float = _um_now() - float(g.get_meta("hf_boss_rt")) - Bal.v("fx/hf_boss_wait", 0.12)
	var st: float = Bal.v("fx/hf_boss_t", 0.25)
	var et: float = Bal.v("ult/imp_ease", 0.35)
	var lo: float = Bal.v("fx/hf_boss_lo", 0.3)
	if t < 0.0:
		return 1.0
	if t >= st + et:
		g.remove_meta("hf_boss_rt")
		return 1.0
	if t < st:
		return lo
	var k: float = (t - st) / et
	return lerpf(lo, 1.0, k * k)


# ================================================================ 打击感进化（docs/291，11-07 用户给的像素近战文章：蓄力 → 过冲爆发 → 稳重心收招）
## 开关 fx/melee_evo（缺省 0 = 关）+ 按干员 fx/melee_evo_op/<干员>（试点德克萨斯、星熊）。全部只画，不抽 g.rng，不新增顿帧（时钟不变）。
##   ① 过冲前探：命中那一拍本体往目标方向探出 lunge_px（爆发 = 一拍到位），停帧期间保持，之后 lunge_back 秒按 15 fps 节拍退回（收招慢于爆发）；
##   ② 拉丝残影：探出那两拍在原位与探出位之间留 2 个本色渐隐分身（像素拉丝）；
##   ③ 扇形拉丝：本体手部高度朝目标画一道实心扇形色块（不对称月牙：尾细头粗，头部近白），2 拍：满形 → 只剩头部暗带 → 没；按 2 世界像素格逐行画；
##   ④ 巅峰帧：命中第一拍本体提亮（peak）；
##   ⑤ 蹬地尘：命中时脚下往身后扬 dust 颗尘点（g.vrng）。
const EVO_COL := {"texas": Color("#ffac3c")}   # 德克萨斯定稿琥珀次色（docs/257 §10）


static func evo(o) -> bool:
	return o != null and on(o.g) and Bal.v("fx/melee_evo", 0.0) > 0.0 and Bal.v("fx/melee_evo_op/" + str(o.id), 0.0) > 0.0


static func ek(key: String, d: float) -> float:
	return Bal.v("fx/melee_evo_" + key, d)


## 命中时记下（hit / meat 调）：hold 局部停帧秒数（全局顿帧本来就停 g.t，传 0）
static func _evo_hit(o, hits: Array, hold: float, heavy: bool, col: Color) -> void:
	if not evo(o):
		return
	var g = o.g
	var best = null
	var bd := INF
	for e in hits:
		if e is Dictionary:   # 这一下打死的也算（前期几乎刀刀击杀）
			var dd: float = e.pos.distance_squared_to(o.pos)
			if dd < bd:
				bd = dd
				best = e
	if best == null:
		return
	var d: Vector2 = best.pos - o.pos
	var dir: Vector2 = d.normalized() if d.length() > 0.5 else Vector2.RIGHT
	var m: Dictionary = o.get_meta("me_ev", {})
	if not m.is_empty() and g.t - float(m.t) < 1.0 / 15.0:
		return   # 同一拍里的第二下不再重起（高频出刀不抖）
	o.set_meta("me_ev", {"t": g.t, "hold": maxf(0.0, hold), "dir": dir, "reach": clampf(sqrt(bd), 26.0, 64.0), "col": col, "heavy": heavy, "sd": int(g.t * 997.0) % 7})
	var n: int = int(ek("dust", 3.0))
	if n > 0 and g.has_meta("fx_recipe"):
		var R = g.get_meta("fx_recipe")
		R._grains(o, o.pos + Vector2(0, -2), o.pos.y, "dust", n + (1 if heavy else 0), {"c0": Color(0.62, 0.58, 0.52), "c1": Color(0.38, 0.35, 0.32), "grain_spd": 0.7}, -dir)


static func _evo_age(o) -> Array:
	var m: Dictionary = o.get_meta("me_ev", {})
	if m.is_empty() or not evo(o):
		return []
	var age: float = o.g.t - float(m.t)
	if age < 0.0 or age > float(m.hold) + 0.5:
		return []
	return [m, age]


## ① 本体画面偏移（character.draw_body 叠加；判定位置不动）
static func lunge(o) -> Vector2:
	var a := _evo_age(o)
	if a.is_empty():
		return Vector2.ZERO
	var m: Dictionary = a[0]
	var age: float = a[1]
	var b := 1.0 / 15.0
	var px: float = ek("lunge_heavy_px", 7.0) if m.heavy else ek("lunge_px", 4.0)
	var k := 1.0
	var t1: float = float(m.hold) + b
	if age > t1:
		var back: float = maxf(b, ek("lunge_back", 0.2))
		var u: float = floor((age - t1) * 15.0) / 15.0 / back   # 按节拍跳格退回
		if u >= 1.0:
			return Vector2.ZERO
		k = (1.0 - u) * (1.0 - u)   # 先退得快、最后稳住（收招有落地感）
	return ((m.dir as Vector2) * px * k / 2.0).round() * 2.0


## ④ 本体提亮倍数
static func peak(o) -> float:
	var a := _evo_age(o)
	if a.is_empty() or float(a[1]) >= 1.0 / 15.0:
		return 1.0
	return ek("peak", 1.7)


## ②③ 画在本体下面（character.draw_body 在画本体之前调）
static func draw_under(o, st: Dictionary, base: Vector2, foot_dx: float, foot_off: float) -> void:
	var a := _evo_age(o)
	if a.is_empty():
		return
	var m: Dictionary = a[0]
	var age: float = a[1]
	var g = o.g
	var beat: int = int(floor(age * 15.0))
	var hb: int = int(floor(float(m.hold) * 15.0))   # 停帧期间扇形停在第一拍
	var ph: int = beat - hb if beat > hb else 0
	if ek("fan", 1.0) > 0.0 and ph <= 1:
		_fan(o, m, base, ph)
	if ek("smear", 1.0) > 0.0 and ph <= 1:
		var ln: Vector2 = lunge(o)
		var c: Color = (m.col as Color).lerp(Color.WHITE, 0.25)
		var al: Array = [0.42, 0.2] if ph == 0 else [0.2, 0.0]
		for i in 2:
			if float(al[i]) <= 0.0:
				continue
			var p: Vector2 = base + (ln * (0.5 - 0.5 * i) - (m.dir as Vector2) * 4.0 * i / 2.0).round()
			o.draw_sprite_at(p + Vector2(foot_dx, 0), st.flip, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, float(al[i])), st.frame, st.tex, st.hf, foot_off)


static func _fan(o, m: Dictionary, base: Vector2, ph: int) -> void:
	var g = o.g
	var cv = o.cv
	var dir: Vector2 = m.dir
	var c0: Vector2 = base + Vector2(0, -ek("hand_y", 20.0)) + dir * 4.0
	var R1: float = float(m.reach) * ek("fan_reach", 0.8) * (1.15 if m.heavy else 1.0)
	var R0: float = R1 * 0.38
	var sw: float = deg_to_rad(ek("fan_deg", 84.0))
	var flip: float = -1.0 if dir.x < 0.0 else 1.0   # 自上而下挥：尾在上、头在目标方向略偏下
	var a_head: float = dir.angle() + 0.18 * flip
	var a_tail: float = a_head - sw * flip
	var col: Color = m.col
	var cc: Color = col.lerp(Color.WHITE, 0.15)
	var hot: Color = col.lerp(Color.WHITE, 0.85)
	var aa: float = ek("fan_alpha", 0.9)
	var s := 2.0   # 美术像素格（世界 2 px）
	var bx := Rect2(c0 - Vector2(R1, R1), Vector2(R1, R1) * 2.0)
	var y: float = floor(bx.position.y / s) * s
	while y < bx.end.y:
		var x: float = floor(bx.position.x / s) * s
		var run_x := -1.0
		var run_c := Color(0, 0, 0, 0)
		while x <= bx.end.x + s:
			var q: Vector2 = Vector2(x + s * 0.5, y + s * 0.5) - c0
			var cell := Color(0, 0, 0, 0)
			var r: float = q.length()
			if r <= R1 and r >= R0 * 0.6:
				var da: float = wrapf((q.angle() - a_tail) * flip, -PI, PI)
				var u: float = da / sw   # 0 尾 → 1 头
				if u >= 0.0 and u <= 1.0:
					var th: float = lerpf(2.0, (R1 - R0) * ek("fan_th", 0.5), pow(u, 0.8))   # 月牙：尾一格细、头部最厚
					var inner: float = R1 - th + 2.0 * sin(u * 11.0 + float(m.sd)) * u   # 内缘略不规整
					if ph == 1:
						inner = maxf(inner, R1 - lerpf(2.0, 6.0, u))   # 第二拍只剩头部外缘暗带
					if r >= inner:
						var lv: float = 0.35 if u < 0.33 else (0.65 if u < 0.66 else 1.0)   # 尾巴渐隐（三阶，不做平滑渐变）
						if ph == 0:
							if r > R1 - 2.5 and u > 0.25:
								cell = hot   # 外缘一格热白
							elif r < inner + 2.5:
								cell = col.darkened(0.35)   # 内缘一格压暗，读出体积
							else:
								cell = cc
						else:
							cell = col.darkened(0.3)
							lv *= 0.6
						cell.a = lv
			if cell != run_c:
				if run_c.a > 0.0:
					cv.draw_rect(Rect2(run_x, y, x - run_x, s), Color(run_c.r, run_c.g, run_c.b, run_c.a * aa))
				run_c = cell
				run_x = x
			x += s
		if run_c.a > 0.0:
			cv.draw_rect(Rect2(run_x, y, x - run_x, s), Color(run_c.r, run_c.g, run_c.b, run_c.a * aa))
		y += s


## 表现时钟（ui_motion.now）：运行时 load，不 preload——ui_motion 引用自动加载 Cfg，核心契约测试（-s 脚本模式）里会编译失败
static func _um_now() -> float:
	return load("res://scripts/ui_motion.gd").now()
