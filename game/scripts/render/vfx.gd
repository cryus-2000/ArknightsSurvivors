extends RefCounted
## 特效与提示：帧条特效（V6_FRAMES 的 fx_*）、旧式整条动画、刀光 / 爪痕、火花、飘字、横幅、屏幕震动；
## 加色混合层（fx_add 节点）的绘制；特效与各种提示计时的逐帧衰减。干员经 characters/op_api.gd 调用。2026-09-26 从 game.gd 拆出。

const A = preload("res://scripts/art.gd")
const UI = preload("res://scripts/ui.gd")
const D = preload("res://scripts/data.gd")

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
		_boss_sum.append({"e": e, "dmg": dmg, "t": BOSS_SUM_T, "weak": weak})
		return
	if _boss_fight():
		return
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
		if s.dmg >= 1.0:
			add_text(e.pos + Vector2(g.vrng.randf_range(-8, 8), -e.r - 14), ("弱点 " if s.weak else "") + str(int(round(s.dmg))), Color(1.0, 0.85, 0.35) if s.weak else Color(1, 0.92, 0.95), 18)
	_boss_sum = _boss_sum.filter(func(s): return s.t > 0.0)


func add_text(pos: Vector2, text: String, col: Color, size := 14) -> void:
	if text.is_valid_int():
		for i in range(g.texts.size() - 1, maxi(-1, g.texts.size() - 25), -1):
			var t: Dictionary = g.texts[i]
			if t.max - t.life > TEXT_MERGE_T or t.col != col or not str(t.text).is_valid_int() or t.pos.distance_to(pos) > TEXT_MERGE_R:
				continue
			if t.get("base", t.size) != size:
				continue
			t["base"] = t.get("base", t.size)
			t.text = str(int(t.text) + int(text))
			t.size = mini(t.base + 6, t.size + 1)
			t.life = t.max
			return
	g.texts.append({"pos": pos, "text": text, "col": col, "life": 0.65, "max": 0.65, "size": size})
	if g.texts.size() > TEXT_CAP:
		g.texts.pop_front()


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
const HINT_WORDS := ["加入编队", "加入支援", "升至 Lv", "精英化", "音乐："]
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
	if g.balance:
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
func fx_sprite(name: String, pos: Vector2, scale := Game.PX, ang := 0.0, flip := false, bottom := false, col := Color.WHITE) -> bool:
	if g.tex.get(name) == null:
		return false
	if name.begins_with("fx_slash") or name.begins_with("fx_claw"):
		scale = blade_scale(scale)
	scale = minf(scale, FX_SCALE_MAX)
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
