extends RefCounted
## 特效与提示：帧条特效（V6_FRAMES 的 fx_*）、旧式整条动画、刀光 / 爪痕、火花、飘字、横幅、屏幕震动；
## 加色混合层（fx_add 节点）的绘制；特效与各种提示计时的逐帧衰减。干员经 characters/op_api.gd 调用。2026-09-26 从 game.gd 拆出。

const A = preload("res://scripts/art.gd")
const UI = preload("res://scripts/ui.gd")
const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")

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
func impact_pause(seconds: float) -> void:
	if g.t < impact_at:
		impact_at = -99.0
	if g.t - impact_at < 0.28 and absf(g.t - impact_at) > 0.0001:
		return
	impact_at = g.t
	g.hitstop = maxf(g.hitstop, clampf(seconds, 0.0, 0.075))


func contact(oid: String, e: Dictionary, origin: Vector2, source := "") -> void:
	var prev: float = contact_at.get(oid, -99.0)
	if g.t >= prev and g.t - prev < 0.18:
		return
	contact_at[oid] = g.t
	if (e.pos as Vector2).distance_to(g.ppos) > 650.0:
		return
	var heavy: bool = oid in ["ulpianus", "siege", "saria", "kaltsit", "wisadel"]
	var melee: bool = oid in ["mizuki", "skadi", "specter_unchained", "irene"]
	var color := Color(0.72, 0.84, 0.92) if heavy or melee else Color(0.55, 0.65, 0.92)
	var direction: Vector2 = (e.pos - origin).normalized()
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

func hit_react(e: Dictionary, crit: bool, weak: bool) -> void:
	var h: Dictionary = g.hit
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
	e.flash = maxf(float(e.get("flash", 0.0)), fl)
	e.squash = maxf(float(e.get("squash", 0.0)), sq)
	# 受击后坐（docs/53，纯画面）：本体沿「远离主控」的方向顶开 fx/recoil_px，fx/recoil_t 秒内回位；技能 / 暴击 / 弱点 ×fx/recoil_skill_k。
	# 只写 rc_at / rc_dir / rc_k 三个字段，位移在 render/world.gd 的 _eoff 里按 g.t 算（缓存路径和原路径同一个表达式，不进签名）。
	# 持续伤害不顶；Boss 不顶（韧性的观感，Boss 的受击反馈走破绽）
	if not dot and not e.get("boss", false):
		var d: Vector2 = (e.pos as Vector2) - g.ppos
		e.rc_dir = d.normalized() if d.length_squared() > 1.0 else Vector2(1.0, 0.0)
		e.rc_at = g.t
		e.rc_k = Bal.v("fx/recoil_skill_k", 1.6) if (skill or crit or weak) else 1.0
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
		g.fx.append({"kind": "ring", "pos": head, "r": float(e.get("r", 20.0)) * 0.9 + 14.0, "life": 0.22, "max": 0.22, "col": Color(1.6, 1.25, 0.45)})
		impact_pause(Bal.v("fx/break_pause", 0.035))


## 击杀爆点按体型分档（docs/53，combat.kill 调用；纯画面 + 音效，粒子用 g.vrng，不碰 g.rng）：
## - 火花数 = fx/kill_sparks + e.r × fx/kill_sparks_per_r，速度随体型略增；冲击环照旧 e.r × 1.2
## - 大体型（e.r ≥ fx/kill_big_r）：再加一圈慢扩散的外环 + 脚下尘土 + 材质层音（甲壳 fx/kill_shell_sfx = kill_shell，其余 fx/kill_big_sfx = kill_big）
## - 击杀音 kill 的音高按体型降（fx/kill_pitch_r：r 越大越低），同屏一片小怪倒下时也听得出大小
## - 顿帧：大体型或暴击击杀 impact_pause(fx/kill_pause)，走共享预算（0.28 秒最多一次，受「命中顿帧」设置）
func kill_burst(e: Dictionary, col: Color, crit: bool) -> void:
	var r: float = float(e.get("r", 12.0))
	var big: bool = r >= Bal.v("fx/kill_big_r", 20.0)
	var n: int = Bal.vi("fx/kill_sparks", 7) + int(r * Bal.v("fx/kill_sparks_per_r", 0.3))
	sparks(e.pos, Vector2.ZERO, col, n, 160.0 + r * 3.0)
	g.fx.append({"kind": "ring", "pos": e.pos, "r": r * 1.2, "life": 0.18, "max": 0.18, "col": col})
	var pitch: float = clampf(1.15 - r / maxf(1.0, Bal.v("fx/kill_pitch_r", 60.0)), 0.75, 1.15)
	Sfx.play("kill", -8.0 + (2.0 if big else 0.0), pitch)
	if big:
		g.fx.append({"kind": "ring", "pos": e.pos, "r": r * 2.0, "life": 0.3, "max": 0.3, "col": Color(col.r, col.g, col.b, 0.6)})
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


func _init(game: Game) -> void:
	g = game


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

func dmg_number(e: Dictionary, dmg: float, crit: bool, weak: bool) -> void:
	if not Cfg.dmg_numbers or g.texts.size() >= 80:
		return
	var jit := Vector2(g.vrng.randf_range(-6, 6), 0)
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
	if not weak and g.texts.size() > Bal.vi("fx/text_crowd", 30):
		return   # 飘字多时普通白字不飘，只留暴击 / 弱点 / 破绽（可读性，1.1.1）
	if weak:
		add_text(e.pos + jit + Vector2(0, -e.r - 12), "弱点 " + str(int(round(dmg))), Color(1.0, 0.85, 0.35), 18)
	else:
		add_text(e.pos + jit + Vector2(0, -e.r - 8), str(int(round(dmg))), Color(1, 1, 1, 0.95), 14)


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
			add_text(e.pos + Vector2(g.vrng.randf_range(-8, 8), -e.r - 16), "破绽 " + str(int(round(s.dmg))), UI.GOLD, 22)   # 破绽期间：金色大一号（打击感审查）
		elif s.dmg >= 1.0 and (s.weak or g.texts.size() <= Bal.vi("fx/text_crowd", 30)):
			add_text(e.pos + Vector2(g.vrng.randf_range(-8, 8), -e.r - 14), ("弱点 " if s.weak else "") + str(int(round(s.dmg))), Color(1.0, 0.85, 0.35) if s.weak else Color(1, 0.92, 0.95), 18)
	_boss_sum = _boss_sum.filter(func(s): return s.t > 0.0)


## 敌方特效标记（docs/48 全局 ③）：game.gd 在敌人 AI、敌弹与预警结算前后调用，给这两段里新加进 g.fx 的特效打上 enemy，
## render/world.gd 的后期降噪（fx_dim）跳过它们——敌人的爆炸、斩击、踏地、冲击环不该跟着友方特效一起变淡
func mark_enemy_fx(from: int) -> void:
	for i in range(from, g.fx.size()):
		g.fx[i]["enemy"] = true


func add_text(pos: Vector2, text: String, col: Color, size := 14) -> void:
	var pn: Array = _num_parts(text)
	if not pn.is_empty():
		var mt: float = Bal.v("fx/text_merge_t", TEXT_MERGE_T)
		var mr: float = Bal.v("fx/text_merge_r", TEXT_MERGE_R)
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
	var tries: int = Bal.vi("fx/text_nudge_max", 3)
	var nt: float = Bal.v("fx/text_nudge_t", 0.3)
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
	g.lvup_delay -= dt
	g.lvup_show -= dt
	g.hud_lv_flash = max(0.0, g.hud_lv_flash - dt * 1.5)
	g.xp_flash = maxf(0.0, g.xp_flash - dt * 3.0)
	for f in g.fx:
		f.life -= dt
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
var banner_q: Array = []          # [{text, prio}]
var notices: Array = []           # [{text, t}]
var _boss_words: Array = []

func show_banner(text: String, prio := -1) -> void:
	if prio < 0:
		prio = _guess_prio(text)
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
	if g.banner_t <= 0.0 or prio > banner_prio:
		_banner_now(text, prio)
		return
	banner_q.append({"text": text, "prio": prio})
	banner_q.sort_custom(func(a, b): return a.prio > b.prio)   # sort_custom 不稳定也无妨：同级顺序只影响先后
	while banner_q.size() > BANNER_Q_MAX:
		banner_q.pop_back()


func _banner_now(text: String, prio: int) -> void:
	g.banner = text
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
	if g.banner_t <= 0.0 and not banner_q.is_empty():
		var q: Dictionary = banner_q.pop_front()
		_banner_now(q.text, q.prio)
	for n in notices:
		n.t -= dt
	notices = notices.filter(func(n): return n.t > 0.0)


func _notice(text: String) -> void:
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
	if not fx_sprite(n, e.pos + Vector2(0, -e.r * 0.5), sc, dir.angle() if dir != Vector2.ZERO else g.rng.randf() * TAU):
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
	g.draw_texture_rect_region(tx, Rect2(-an, Vector2(fw, fh)), Rect2(fw * (frame % frames), 0, fw, fh), col)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 一次性帧动画特效（命中 / 爆炸）；素材不存在时返回 false，调用方回退到程序特效
## 播放一条帧条特效：flip 镜像；bottom=true 时 pos 为脚底（帧条底部对齐）
## 普通敌人击杀溶解染成淡紫（docs/48 P1：击杀溶解、经验结晶、敌人描边都是青色，后期连成一片）：
## 经验结晶留青色（拾取物），溶解偏紫、描边偏中性白
const DISSOLVE_TINT := Color(1.0, 0.72, 1.05)

func fx_sprite(name: String, pos: Vector2, scale := Game.PX, ang := 0.0, flip := false, bottom := false, col := Color.WHITE) -> bool:
	if g.tex.get(name) == null:
		return false
	if name.begins_with("fx_slash") or name.begins_with("fx_claw"):
		scale = blade_scale(scale)
	scale = minf(scale, FX_SCALE_MAX)
	if name == "fx_death_dissolve" and col == Color.WHITE:
		col = DISSOLVE_TINT
	var spec: Array = Game.V6_FRAMES[name]
	var dur: float = spec[0] / spec[1]
	var f := {"kind": "sprite", "name": name, "pos": pos, "ang": ang, "scale": scale, "life": dur, "max": dur, "flip": flip, "col": col}
	if bottom:
		var tx: Texture2D = g.tex[name]
		f["anchor"] = Vector2(tx.get_width() / spec[0] / 2.0, tx.get_height() - 1.0)
	g.fx.append(f)
	return true


## 以美术像素为单位绘制横向帧条中的一帧，anchor 为贴图内的锚点（0~1）
func spr(name: String, frames: int, frame: int, pos: Vector2, scale := Game.PX, flip := false, col := Color.WHITE, anchor := Vector2(0.5, 0.5), sq := Vector2.ONE) -> void:
	var tx: Texture2D = g.tex.get(name)
	if tx == null:
		return
	pos += g.draw_off
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	var src := Rect2(fw * (frame % frames), 0, fw, fh)
	var size := Vector2(fw, fh) * scale * sq
	if flip:
		# 以锚点为中心水平镜像
		g.draw_set_transform(pos.round(), 0.0, Vector2(-1, 1))
		g.draw_texture_rect_region(tx, Rect2(-size * anchor, size), src, col)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		g.draw_texture_rect_region(tx, Rect2((pos - size * anchor).round(), size), src, col)


func draw_add_layer() -> void:
	g.draw_off = Vector2.ZERO
	g.map.draw_god_rays(g.fx_add, g.get_viewport_rect().size, g.cam.position)
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
	var size := Vector2(fw, fh) * scale
	ci.draw_texture_rect_region(tx, Rect2((pos - size / 2.0).round(), size), Rect2(fw * (frame % frames), 0, fw, fh))


## Boss 扩展招式只负责外观；伤害和弹幕由 BossPatterns 结算。
# Purely cosmetic identity; warning geometry and damage stay in BossAI.
const BOSS_STYLE := {
	"carmen": [Color(1.0, 0.76, 0.3), "fx_muzzle_flash"],
	"iberia": [Color(1.0, 0.45, 0.2), "fx_muzzle_flash"],
	"path": [Color(0.7, 0.8, 0.95), "fx_circle_steel"],
	"bishop": [Color(0.25, 0.85, 0.9), "fx_water_splash"],
	"archon": [Color(0.5, 0.95, 0.6), "fx_claw_double_green"],
	"immortal": [Color(0.65, 0.75, 1.0), "fx_slash_arc_deep"],
	"paranoia": [Color(0.8, 0.4, 1.0), "fx_circle_ghost"],
	"knight_boss": [Color(0.55, 0.85, 1.0), "fx_knight_impact"],
	"ishar": [Color(0.2, 1.0, 0.85), "fx_water_splash"],
	"izumik": [Color(0.55, 1.0, 0.65), "fx_felspell"]
}

func boss_color(type: String) -> Color:
	return BOSS_STYLE.get(type, [Color(1.0, 0.3, 0.65)])[0]

func boss_signature(w: Dictionary) -> void:
	var e: Dictionary = w.owner
	if not BOSS_STYLE.has(e.type):
		return
	var start := g.fx.size()
	var pos: Vector2 = w.pos
	if e.type in ["carmen", "iberia"]:
		pos = e.pos + Vector2.from_angle(w.get("ang", 0.0)) * 28.0 + Vector2(0, -18)
	fx_sprite(BOSS_STYLE[e.type][1], pos, 2.0)
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
	var type: String = b.get("source_type", "paranoia")
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
# 全部纯画面：只往 g.fx 追加、只用 g.vrng；旋钮在 data/balance.json 的 fx 段，fx/vfx2 = 0 一键全关，
# 各项各有开关；低画质 / 触屏不画常驻环境粒子（ambient_ok），一次性事件粒子按 Cfg.fx_density 减半。
# 新增的 fx 种类：mote（光尘，tb 批）、glow（加色层的柔光，light 贴图）、mire_recoil（溟痕退散的收缩环）
# =====================================================================
var p2 := true                 # 运行时总开关（--vfxab=N 同局轮换测量用；缺省开）
var _k2: Dictionary = {}       # fx 段快照（每帧读的旋钮不走 Bal.v 的字符串拆分）
var _lamp_prev := -1.0         # 灯火观察（update_visuals 调 watch_lamp）
var _lamp_ember_acc := 0.0
var _merchant_on := false
var _merchant_acc := 0.0
var _elite_seen := {}
var _sight := {}               # docs/54 §7「首次入画」：精英 id → 登场动画起点（g.t）；fx/first_sight = 0 时不用
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


## 本项是否开着（总开关 × 单项旋钮）
func on(name: String) -> bool:
	return p2 and _kv("vfx2", 1.0) > 0.0 and _kv(name, 1.0) > 0.0


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


## 「首次入画」（docs/54 §7 第 2–3 条，fx/first_sight 缺省 1）：精英登场 / 商人出现的特效改在实体第一次进入视野时播，
## 而不是刷出（多在屏外）那一刻；刷出时就在视野内则和原来一样从刷出算起。纯画面状态，不碰 g.rng
func first_sight() -> bool:
	return _kv("first_sight", 1.0) > 0.0


## 精英本帧要不要走登场动画（world 每帧按视野内的精英调）：首次入画起 0.9 秒内为真
func elite_entrance_due(e: Dictionary) -> bool:
	if not first_sight():
		return e.age < 0.9
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
	return p2 and _kv("vfx2", 1.0) > 0.0 and Cfg.quality != "low" and not Cfg.touch_device()


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
	if not on("beacon_burst2"):
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
		g.fx.append({"kind": "mire_recoil", "pts": cleared.slice(0, 24), "from": pos, "life": 0.75, "max": 0.75, "tex": strip("fx_mire_dissolve")})
		for c in cleared.slice(0, 8):
			motes(c[0], Vector2.UP, Color(0.9, 0.55, 1.4, 0.8), 4, 60.0, 0.9, -30.0, 1.0, 2.0, 1.2, float(c[1]) * 0.5)


## ② 升级（pickups.levelup_fx 调用；原有的双环 + 18 火花 + 头顶字样照旧）：主控柔光 + 金色光柱 + 上升光尘 + 轻微全屏白闪
func levelup_burst(pos: Vector2) -> void:
	if not on("levelup_burst"):
		return
	glow(pos + Vector2(0, -24), 170.0, Color(1.0, 0.85, 0.45, 0.6), 0.55, 0.5)
	if strip("fx_levelup_pillar"):
		# 光柱帧条（32×160 × 6，12 fps，加色层，脚底对齐；按 0.75 倍画成 240 高，免得盖到半屏）
		add_strip("fx_levelup_pillar", pos + Vector2(0, 8), Game.PX * 0.75, Color(1.0, 0.92, 0.7, 0.9), Vector2(16, 159))
	else:
		g.fx.append({"kind": "pillar", "pos": pos + Vector2(0, 8), "life": 0.55, "max": 0.55, "col": Color(1.0, 0.85, 0.4)})
	motes(pos + Vector2(0, -10), Vector2.UP, Color(2.0, 1.7, 0.9), Bal.vi("fx/levelup_motes", 24), 140.0, 1.3, -60.0, 1.0, 2.0, 1.1, 22.0, true)
	g.flash = maxf(g.flash, Bal.v("fx/levelup_flash", 0.25))


## ③ 灯火：render/world.update_visuals 每帧调；跌破 30（暗淡）或归零（寂灭）那一刻暗红一压 + 灯里掉余烬；
## 灯火 < 30 时常驻每秒 fx/lamp_low_embers 粒余烬从灯里飘出（ambient_ok 才画）
func watch_lamp(rd: float) -> void:
	if g.state != g.S.PLAY or g.demo_op != "":
		_lamp_prev = g.lamp
		return
	if _lamp_prev >= 0.0 and on("lamp_dim"):
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
	if g.lamp < 30.0 and g.lamp > 0.0 and ambient_ok() and on("lamp_dim"):
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
	if first_sight() and _sight.has(key):
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
	if not on("promote_burst"):
		return
	var c := Color(1.0, 0.85, 0.45) if elite else Color(0.6, 0.95, 1.0)
	glow(pos + Vector2(0, -24), 150.0 if elite else 100.0, Color(c.r, c.g, c.b, 0.6), 0.6, 0.4)
	motes(pos + Vector2(0, -10), Vector2.UP, Color(c.r * 2.0, c.g * 1.8, c.b * 1.3), 18 if elite else 10, 130.0, 1.2, -60.0, 1.0, 2.0, 1.2, 18.0)
	if elite:
		g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -20), "life": 0.45, "max": 0.45, "col": c})
		g.fx.append({"kind": "pillar", "pos": pos + Vector2(0, 8), "life": 0.6, "max": 0.6, "col": c})


## ⑦ 拾取（pickups 调用）：油 / 治疗 / 磁铁 / 源石锭 / 宝箱各一小段，颜色跟物品色
func pickup_burst(kind: String, col: Color) -> void:
	if not on("pickup_burst"):
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
	if here and on("merchant_fx"):
		if first_sight():
			# 首次入画才放（docs/54 §7 第 3 条）：刷在屏外时等玩家找到它那一刻；刷在视野内则当帧就放
			if not _merchant_seen and _wv().view_rect(40.0).has_point(g.merchant.pos):
				_merchant_seen = true
				burst = true
		else:
			burst = not _merchant_on
	if burst:
		var mp: Vector2 = g.merchant.pos
		glow(mp + Vector2(0, -30), 150.0, Color(1.0, 0.75, 0.45, 0.6), 0.9, 0.3)
		g.fx.append({"kind": "ring", "pos": mp + Vector2(0, 10), "r": 90.0, "life": 0.6, "max": 0.6, "col": Color(1.0, 0.8, 0.5)})
		motes(mp + Vector2(0, -20), Vector2.UP, Color(1.9, 1.5, 0.9), 14, 110.0, 1.3, -40.0, 1.0, 2.0, 1.2, 16.0)
	_merchant_on = here
	if here and ambient_ok() and on("merchant_fx") and g.merchant.pos.distance_to(g.ppos) < 900.0:
		_merchant_acc += rd * _kv("merchant_motes", 1.5)
		if _merchant_acc >= 1.0:
			_merchant_acc -= 1.0
			motes(g.merchant.pos + Vector2(-10, -34), Vector2.UP, Color(1.8, 1.3, 0.7, 0.8), 1, 25.0, 1.6, -12.0, 0.4, 2.0, 0.8, 6.0)
	else:
		_merchant_acc = 0.0


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
