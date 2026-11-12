## 世界层敌方弹幕绘制（world._draw_ebullets_lobs_shocks 与 _eb_* 小函数）。docs/286 §4 第三批从 render/world.gd 原样拆出，行为不变。
## 全部是 static func，第一个参数 wv = world（render/world.gd 实例）；成员经 wv.、常量经 W.。
extends RefCounted

const W = preload("res://scripts/render/world.gd")
const MidCardDraw = preload("res://scripts/render/mid_card_draw.gd")   # 塑路者 / 接潮组弹体与预警（docs/170）
const BossBeam = preload("res://scripts/render/boss_beam.gd")   # Boss 改版样板：Kanpelle 光束、骑士寒气圈 / 寒冷条（docs/142b）
const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")
const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错


static func _draw_ebullets_lobs_shocks(wv: W) -> void:
	var g: Game = wv.g
	# 敌方弹幕分三遍画（性能 9/30：原来每颗子弹影子 / 底圈 / 光晕 / 贴图 / 描边交替，有贴图和无贴图来回切，每颗约 5 次绘制调用；
	# 分遍后同类连续提交能合批）：① 无贴图：影子椭圆、深色底圈、光晕；② 贴图：弹体；③ 无贴图：弹芯、亮描边
	var blades: Array = []
	var mcs: Array = []   # 中期 Boss 分级弹（docs/170，render/mid_card_draw 单独画）
	wv.bbv2.draw(wv)   # 第二版画法的 Boss 弹（影子 / 地面光 / 弹体 / 粒子）先画，下面各遍跳过这些弹
	for b in g.ebullets:
		if b.life <= 0.0 or b.get("own_draw", false) or wv.bbv2.mine(b):
			continue   # 命中 / 到期、还没被回收的敌弹不画（同我方子弹；正式局 _cleanup 每帧回收，图鉴演示由 enemy_demo 回收）；own_draw = 弹体由 Boss 自己画（偏执泡影二阶段，docs/170）
		if b.get("kind", "") == "boss_blade":
			blades.append(b)
			continue
		if b.get("mc", false):
			mcs.append(b)
			continue
		# 2.5D：子弹在离地约 16px 的高度飞行，影子落在判定位置（椭圆直接算顶点，不切画布变换）
		var vk: float = wv.bulfx.k(b)   # 出现动画缩放（只画面，判定半径 b.r 不变）
		wv.tb_circle(b.pos + Vector2(0, 2), (b.r + 1.0) * vk, Color(0, 0, 0, 0.4), 0.45, 10)
		if wv._bullet_tex(b) != "":
			continue   # 专属弹体帧条（docs/96：漂移体侵蚀弹）自带 #080E18 描边，不垫底圈、不描洋红边
		var bp: Vector2 = _ebp(wv, b)
		# 敌方弹幕高对比：深色外圈垫底，画完再描一圈亮洋红边，压在友方特效上也一眼看得出
		wv.tb_circle(bp, (b.r + 3.0) * vk, Color(0.02, 0.0, 0.05, 0.85))
		if g.optical_on:
			var ec: Color = g.optical.eb_col(b)   # 光学观感颜色语言：杂兵弹敌弹色、Boss 弹危险色（docs/139 §6.7 / §7.3）
			wv.tb_circle(bp, (b.r + 4.0) * vk, Color(ec.r, ec.g, ec.b, 0.3))
			continue
		match b.get("kind", "orb"):
			"acid":
				wv.tb_circle(bp, (b.r + 5.0) * vk, Color(0.5, 1.4, 0.3, 0.3))
			"nova":
				wv.tb_circle(bp, (b.r + 5.0) * vk, Color(1.2, 0.4, 1.8, 0.3))
			"nerve":
				wv.tb_circle(bp, (b.r + 5.0) * vk, Color(1.0, 0.9, 0.3, 0.25))
			_:
				wv.tb_circle(bp, (b.r + 4.0) * vk, Color(1.0, 0.3, 0.6, 0.25))
	wv.tb_flush()
	for b in g.ebullets:
		if b.life <= 0.0 or b.get("mc", false) or b.get("own_draw", false) or wv.bbv2.mine(b):
			continue
		var kd: String = b.get("kind", "orb")
		var bp: Vector2 = _ebp(wv, b)
		var btex: String = wv._bullet_tex(b)
		var vk: float = wv.bulfx.k(b)
		if btex != "":
			# 小怪专属弹体（enemies.json shot_tex，docs/96 第 1 批：漂移体 proj_skimmer_corrode）：朝右绘制、按速度方向旋转，帧率按 V6_FRAMES
			var bspec: Array = Game.V6_FRAMES[btex]
			g.vfx.spr_rot(btex, int(g.t * float(bspec[1]) + b.pos.x * 0.01) % int(bspec[0]), bp, b.vel.angle(), Game.PX * vk)
		elif kd == "nerve" and g.tex.get("proj_floater_nerve") != null:
			# 浮海飘航者神经弹（V8 proj_floater_nerve，朝右绘制按速度方向旋转）
			g.vfx.spr_rot(_eb_tex(wv, b, "proj_floater_nerve"), int(g.t * 12.0 + b.pos.x * 0.01) % 4, bp, b.vel.angle(), Game.PX * vk, _eb_mod(wv, b, Color.WHITE))
		elif kd == "acid" and g.tex.get("proj_acid") != null:
			g.vfx.spr("proj_acid", 2, int(g.t * 8.0 + b.pos.x * 0.01) % 2, bp, wv._hpx("proj_acid") * vk, false, Color(1.5, 1.5, 1.5))   # Codex v14 酸团（暗橄榄，避开友方黄绿）；×1.5 提亮，压过地图暗环境光（原程序圆也是过曝色）
		elif kd == "nova" and g.tex.get("proj_nova") != null:
			g.vfx.spr(_eb_tex(wv, b, "proj_nova"), 4, int(g.t * 10.0 + b.pos.x * 0.01) % 4, bp, wv._hpx("proj_nova") * _eb_pulse(wv, b) * vk, false, _eb_mod(wv, b, Color(1.5, 1.5, 1.5)))   # Codex v14 新星弹；×1.5 提亮同上；Boss 弹 = 专属色
		elif kd != "acid" and kd != "nova" and kd != "nerve" and kd != "boss_blade":
			g.vfx.spr(_eb_tex(wv, b, "ebullet"), 1, 0, bp, Game.PX * b.r / 5.0 * _eb_pulse(wv, b) * vk, false, _eb_mod(wv, b, Color.WHITE))
	var eb_ow: float = Bal.v("render/ebullet_outline", 0.0) if g.optical_on else 0.0
	for b in g.ebullets:
		var kd: String = b.get("kind", "orb")
		if kd == "boss_blade" or kd == "mc" or b.life <= 0.0 or b.get("own_draw", false) or wv.bbv2.mine(b):
			continue
		var bp: Vector2 = _ebp(wv, b)
		var vk: float = wv.bulfx.k(b)
		var br: float = b.r * vk   # 出现动画缩放后的画面半径（判定仍是 b.r）
		if wv._bullet_tex(b) != "":
			if eb_ow > 0.0:   # 专属弹体（漂移体侵蚀弹）也加同一圈外描边
				var dc0: Color = g.optical.col_danger
				wv.tb_ring(bp, br + 3.0 + eb_ow * 0.5, eb_ow, Color(dc0.r, dc0.g, dc0.b, 1.0))
			continue
		match kd:
			"acid":
				if g.tex.get("proj_acid") == null:
					wv.tb_circle(bp, br, Color(0.6, 1.8, 0.4))
					wv.tb_circle(bp + Vector2(-1.5, -1.5), 1.5, Color(2.2, 2.4, 1.6), 1.0, 6)
			"nova":
				if g.tex.get("proj_nova") == null:
					wv.tb_circle(bp, br, b.get("col", Color(1.5, 0.6, 2.0)))
			"nerve":
				if g.tex.get("proj_floater_nerve") == null:
					wv.tb_circle(bp, br, Color(1.8, 1.6, 0.5))
		if b.has("core_r"):
			wv.tb_circle(bp, float(b.core_r) * vk, b.get("core_col", Color(1.8, 1.7, 1.5)))   # 弹体分级：大弹发光核心（圣徒符卡，docs/171）
		if g.optical_on:
			var ebc: Color = g.optical.eb_col(b)
			var bk: float = 1.3 if b.get("boss", false) else 2.0   # Boss 弹专属色亮描边只提到 ×1.3（×2 叠辉光后色相偏）
			wv.tb_ring(bp, br + 2.0, 1.5, Color(ebc.r * bk, ebc.g * bk, ebc.b * bk, 0.9))   # 亮描边改敌弹色（原亮洋红）；Boss 弹 = 专属色
			var ow: float = eb_ow
			if ow > 0.0:
				# docs/139 §7 敌弹外描边（用户 10-24「敌方子弹加一个描边看一下」）：危险色、不闪，宽 ow 世界像素（2 = 1 个低分辨率格），压在亮描边外侧
				var dc: Color = g.optical.col_danger
				wv.tb_ring(bp, br + 3.0 + ow * 0.5, ow, Color(dc.r, dc.g, dc.b, 1.0))
			_eb_boss_outline(wv, b, bp, br)
			if wv.bfx_grains != null and b.get("boss", false) and g.vrng.randf() < 0.08 and BossBeam.take(g, 1) > 0:
				wv.bfx_grains.push("mote_shed", bp, -b.vel.normalized(), ebc)   # 沿途散颗粒（拖尾之外的「活」，走预算）
		elif b.get("boss", false):
			var bc: Color = g.vfx.boss_color(str(b.get("src_type", "")))
			wv.tb_ring(bp, br + 2.0, 1.5, Color(bc.r * 1.3, bc.g * 1.3, bc.b * 1.3, 0.9))   # Boss 弹亮描边 = 专属色（不加危险色外圈，用户 10-25「描边不要加」）
			_eb_boss_outline(wv, b, bp, br)
		else:
			wv.tb_ring(bp, br + 2.0, 1.5, Color(2.4, 0.8, 1.8, 0.9))
	wv.tb_flush()
	for b in blades:
		g.vfx.boss_blade(b, b.pos + Vector2(0, -16))
	if not mcs.is_empty():
		MidCardDraw.bullets(wv, g, mcs)
	# 抛射碎石 / 投嗣弹：落点预警 + 空中石块（投嗣育母投出的拟嗣：低弧，弹体 proj_mother_brood，缺图时 e_brood 基础帧缩小旋转）
	for l in g.lobs:
		var k: float = l.t / l.dur
		var brood: bool = l.get("kind", "") == "brood"
		# 抛石落点的地面椭圆预警 10-22b 用户取消（g.lobs 只有普通怪的抛射，Boss 抛射走 g.warns）：只画空中的石块 / 投嗣弹
		var gp: Vector2 = l.from.lerp(l.to, k)
		var hgt := sin(k * PI) * (80.0 if brood else 120.0)
		g.wcv.draw_set_transform(gp, 0.0, Vector2(1.0, 0.45))
		g.wcv.draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.35))
		g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var rp := gp + Vector2(0, -hgt - 8.0)
		var ltex: String = str(l.get("tex", ""))
		if brood:
			var spin: float = k * TAU * 1.5 * (1.0 if l.to.x >= l.from.x else -1.0)   # 顺着飞行方向翻滚一圈半
			if g.tex.get("proj_mother_brood") != null:
				g.vfx.spr_rot("proj_mother_brood", int(g.t * 12.0 + l.from.x * 0.01) % 4, rp, spin, wv._hpx("proj_mother_brood"))
			else:
				var bt: Texture2D = g.tex.get("e_brood")
				if bt != null:
					var bw: float = bt.get_width() / 2.0
					var bh: float = float(bt.get_height())
					var bs: float = wv._hpx("e_brood") * 0.8
					g.wcv.draw_set_transform(rp + g.draw_off, spin, Vector2(bs, bs))
					g.wcv.draw_texture_rect_region(bt, Rect2(-Vector2(bw, bh) / 2.0, Vector2(bw, bh)), Rect2(0, 0, bw, bh), Color(1.15, 1.15, 1.15))
					g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					g.wcv.draw_circle(rp, 6.0, Color(0.85, 0.55, 0.75))
		elif ltex != "" and g.tex.get(ltex) != null:
			# 专属抛射物（enemies.json lob_tex，docs/96 第 1 批：喷吐者酸团 proj_spitter_acid 4 帧循环），沿同一条 lob 轨迹
			var lspec: Array = Game.V6_FRAMES[ltex]
			g.vfx.spr(ltex, int(lspec[0]), int(g.t * float(lspec[1])) % int(lspec[0]), rp, wv._hpx(ltex))
		elif g.tex.get("proj_rock_shard") != null:
			g.vfx.spr("proj_rock_shard", 4, int(g.t * 12.0) % 4, rp, wv._hpx("proj_rock_shard"))   # Codex v14 碎石（翻滚画在帧里）
		else:
			g.wcv.draw_circle(rp, 7.0, Color(0.45, 0.42, 0.4))
			g.wcv.draw_circle(rp + Vector2(-2, -2), 3.0, Color(0.7, 0.66, 0.6))
	# 冲击环（docs/48 全局 ④⑤、P0 伊祖米克）：原来写死成治疗同款的绿色、越扩越淡，到主控这里几乎看不见。
	# 改成敌方危险色：深色外描边 + 洋红紫主色 + 白芯，透明度下限 0.6，扩到最大也看得清
	for sh in (g.shocks if not wv._dbg_shock else []):   # --clutterdbg=noshock 量测（docs/139 §8）
		if not sh.get("ground", false):
			wv._draw_shock(sh)


## 敌方弹幕三遍（无贴图底 → 贴图 → 弹芯描边）+ Boss 刀刃 → 抛射碎石 → 冲击环
## Boss 弹画灰度弹体再乘专属色（_eb_gray 从原图做：optical._eb_step 把杂兵弹换成青蓝色相时，原图留在 g.tex[名 + "@boss"]；
## docs/139 §7.3、docs/142b §8.4；旧开关 render/ebullet_boss_own 10-29 已删）
static func _eb_tex(wv: W, b: Dictionary, nm: String) -> String:
	return _eb_gray(wv, nm) if b.get("boss", false) else nm


## 敌弹画在哪：脚下 16 像素上方；Boss 弹再加一点垂直于飞行方向的轻摆（±2，按所在位置错相——同一圈弹各摆各的，飞起来是一条条细波，不是整片平移）。只画面
static func _ebp(wv: W, b: Dictionary) -> Vector2:
	var g: Game = wv.g
	var p: Vector2 = b.pos + Vector2(0, -16)
	if b.get("boss", false) and wv.bfx_grains != null:
		var v: Vector2 = b.vel
		if v.length_squared() > 1.0:
			p += v.orthogonal().normalized() * sin(g.t * 9.0 + (b.pos.x + b.pos.y) * 0.06) * 2.0
	return p


## Boss 弹体脉动（±14%，错相同上）；不是 Boss 弹或颗粒关着时 1
static func _eb_pulse(wv: W, b: Dictionary) -> float:
	var g: Game = wv.g
	if not (b.get("boss", false) and wv.bfx_grains != null):
		return 1.0
	return 1.0 + 0.14 * sin(g.t * 13.0 + (b.pos.x - b.pos.y) * 0.05)


## Boss 弹体的调色：专属色 × 1.1（只略提亮：再高光学辉光一叠色相就偏，炮火橙会变黄；docs/142b §8.4，不加危险色外圈，
## 用户 10-25「描边不要加」）；不是 Boss 弹时用 base
static func _eb_mod(wv: W, b: Dictionary, base: Color) -> Color:
	var g: Game = wv.g
	if not b.get("boss", false):
		return base
	if b.has("bcol"):
		return b.bcol   # 弹自带弹芯色（伊莎玛拉按幕换色，docs/170 §15）
	var t: String = str(b.get("src_type", ""))
	var c: Color = b.own_col if b.has("own_col") else D.ENEMIES.get(t, {}).get("bcol_core", g.vfx.boss_color(t))   # 有弹芯色（伊比利亚）用弹芯色；own_col = 弹自带专属色（伊祖米克分幕，docs/170 §16）
	return Color(c.r * 1.1, c.g * 1.1, c.b * 1.1)


## Boss 弹的同色系外描边（enemies.json bcol_outline，目前只伊比利亚，用户 10-25「描边要同调、有层次」）：压在亮边外侧、2 世界像素（1 个低分辨率格）、不闪
static func _eb_boss_outline(wv: W, b: Dictionary, bp: Vector2, br := -1.0) -> void:
	if not b.get("boss", false):
		return
	var oc = D.ENEMIES.get(str(b.get("src_type", "")), {}).get("bcol_outline")
	if oc is Color:
		wv.tb_ring(bp, (b.r if br < 0.0 else br) + 3.5, 2.0, Color(oc.r, oc.g, oc.b, 1.0))


## 弹体贴图的灰度版 g.tex[名 + "@gray"]（第一次用时从原色版做：按最亮通道提到 0.35–1.0 的灰、保留透明度），画时乘专属色。纯画面
static func _eb_gray(wv: W, nm: String) -> String:
	var g: Game = wv.g
	var key: String = nm + "@gray"
	if g.tex.has(key):
		return key
	var src: Texture2D = g.tex.get(nm + "@boss", g.tex.get(nm))
	if src == null:
		return nm
	var im: Image = src.get_image()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	for y in im.get_height():
		for x in im.get_width():
			var c: Color = im.get_pixel(x, y)
			if c.a > 0.0:
				var v: float = clampf(0.35 + maxf(c.r, maxf(c.g, c.b)) * 0.75, 0.0, 1.0)
				im.set_pixel(x, y, Color(v, v, v, c.a))
	g.tex[key] = ImageTexture.create_from_image(im)
	return key
