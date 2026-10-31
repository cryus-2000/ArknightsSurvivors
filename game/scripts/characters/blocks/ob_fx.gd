## 干员积木 · ob_fx（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/ob_check.gd"


# ================================================================ 画面帧条 fx（docs/61 §5.6，10-11 加；纯画面，追加式）
## 任何积木（以及 blocks.skills[i] 本身）可以带 "fx": [条目…]，把 game.gd V6_FRAMES 里登记的帧条挂到出手 / 技能发动 / 常驻光环上。
## 不写 fx 的干员画法与原来逐像素相同；fx 只往干员自己的 pfx 里加粒子、散布只用 g.vrng，不碰 g.rng / 玩法状态（同 seed TRACE / BALANCE 不变）。
## 缺图（g.tex 没有这条）时静默跳过，程序画法照旧作底。


const FX_KEYS := ["strip", "vortex", "cond", "at", "layer", "fit", "scale", "max_scale", "n", "spread", "rise", "life", "every", "tint", "anchor", "off", "ang", "rot",
	"hold", "fade", "no_fade", "inward", "if_tex", "ease", "grow", "grow0", "grow_to", "wake", "xfade",
	"delay", "stay", "once", "face_x", "flash", "along", "play", "on_sprite"]   # on_sprite（10-15）：锚到本干员当前帧的定位点（character.sprite_point，星熊盾心），这一帧没有就退回原锚点 / 贴身层不画；play：精英化第 5 批段（扩散缓动的帧号按 fps 播）；精英化段（docs/91 第 1 批）：延迟起播、末帧停留、区域里不循环、偏移随朝向、开火时提亮

## ground：紧贴地砖（溟痕 / Boss 地面预警 / 掉落之下），只给常驻跟随帧条（hold）用，大片地面特效不盖住危险提示（10-12 加）
const FX_LAYERS := ["floor", "over", "add", "behind", "front", "ground"]

## 常驻跟随帧条（hold: true，10-12 加）：积木生效期间循环、跟着区域中心 / 半径走，缺省淡入淡出秒数（条目 fade 可改）
const FX_HOLD_FADE := 0.3

const FX_HOLD_LAYERS := ["ground", "floor", "add", "over"]   # over：画在人物之上（_draw_skill_over，精英化段：能天使祝福光环挂在队友头顶）

## 贴身层：画在干员本体的后面 / 前面（draw_body 前后），积木生效期间循环，帧号 = floor(生效秒数 × fps) % 帧数，退出时 FX_BODY_FADE 秒淡出
const FX_BODY := ["behind", "front"]

const FX_BODY_FADE := 0.15

## 放大上限（每个 1x 美术像素至多几个世界像素）：同 render/vfx.gd FX_SCALE_MAX，免得颗粒比人物粗太多；条目可用 max_scale 改
const FX_SCALE_MAX := 3.2

const FX_AT := ["center", "self", "leader", "zone", "hits", "orbit", "members", "mate"]   # members：光环的受益者（hold）；mate：出手的那名队友（trig.on_mate_attack）

## 只播一次的 fx 宿主（瞬时积木 / 技能发动 / 触发积木）：不能写 every、贴身层、漩涡（§8 第 9 条）。第三批新积木追加在这里
const FX_INSTANT_OWNERS := ["shape.circle", "shape.cone", "cast", "verb.sp_team",
	"shape.line", "verb.displace", "verb.field", "verb.negate_next", "verb.taunt_guard", "trig.on_hurt", "trig.on_negate", "verb.summon", "verb.shield", "verb.guard",
	"st.stun", "st.slow", "st.airborne", "st.weightless", "st.pause", "shape.boomerang", "verb.summon_cmd", "trig.on_mate_attack"]   # 精英化段（docs/91 第 1 批）

## 能写 at = hits 的宿主（带命中列表的伤害形状）
const FX_HITS_OWNERS := ["shape.circle", "shape.cone", "shape.line"]

## 自己在合适的位置播 fx 的积木：data_operator._exec_list 不再按区域中心替它们播
const FX_SELF_PLAY := ["shape.circle", "shape.cone", "shape.line", "verb.displace", "verb.field", "verb.negate_next", "verb.taunt_guard", "verb.summon", "verb.shield", "verb.heal", "verb.guard",
	"shape.boomerang", "verb.summon_cmd"]

const ArtS = preload("res://scripts/art.gd")


## 瞬时播放：c / r 是出手形状的中心与半径（技能发动、常驻光环时是区域中心与半径），hits 是本次命中的敌人，ang 是锥形的朝向。
## 带 every 的条目（常驻定时播）和 at = orbit 的条目（绕行体常驻贴图）这里跳过
static func fx_play(o, entries, c: Vector2, r: float, hits: Array = [], ang := 0.0) -> void:
	if not (entries is Array):
		return
	for f in entries:
		if _F().hw_fx_is(f):   # 手写迁移段的程序条目（blade 刀光；常驻的 aura_ring / outline 在画的时候按积木生效画）
			if float(f.get("every", 0.0)) <= 0.0 and not fx_is_hold(f) and fx_on(o, f):
				_F().hw_fx_spawn(o, f, {"c": c, "r": r, "hits": hits, "ang": ang})
			continue
		if _F().mf_is(f):   # 召唤物扩展段的程序条目
			if float(f.get("every", 0.0)) <= 0.0 and fx_on(o, f):
				_F().mf_fx_spawn(o, f, {"c": c, "r": r, "hits": hits, "ang": ang})
			continue
		if not (f is Dictionary) or float(f.get("every", 0.0)) > 0.0 or str(f.get("at", "center")) == "orbit" or fx_is_hold(f):
			continue
		if fx_on_spawn(o, f):
			fx_spawn(o, f, c, r, hits, ang)


## 常驻积木上带 every 的条目：ts 是这块积木各条目的画面计时（秒，按条目下标），返回新的计时。积木生效的第一帧就播一次
static func fx_tick(o, entries, c: Vector2, r: float, ts: Array, dt: float) -> Array:
	if not (entries is Array):
		return ts
	if ts.size() != entries.size():
		ts = []
		ts.resize(entries.size())
		ts.fill(INF)
	for i in entries.size():
		var f = entries[i]
		if not (f is Dictionary):
			continue
		var ev: float = float(f.get("every", 0.0))
		if ev <= 0.0 or str(f.get("at", "center")) == "orbit" or fx_is_hold(f):
			continue
		ts[i] = float(ts[i]) + dt
		if ts[i] >= ev:
			ts[i] = 0.0 if ts[i] == INF else fmod(ts[i], ev)
			if fx_on_spawn(o, f):
				if _F().mf_is(f):
					_F().mf_fx_spawn(o, f, {"c": c, "r": r})
				else:
					fx_spawn(o, f, c, r, [], 0.0)
	return ts


static func fx_spawn(o, f: Dictionary, c: Vector2, r: float, hits: Array, ang: float) -> void:
	var g = o.g
	var name: String = str(f.get("strip", ""))
	if g != null and g.vfx != null and g.vfx._fxc != null:   # --fxcensus：@ob = 干员数据特效，L = 循环件 / 扩散件（不粒子化）
		g.vfx._fx_census(name + ("@obL" if (f.has("life") and not f.get("once", false)) or str(f.get("ease", "")) != "" else "@ob"), false)
	if g == null or g.tex.get(name) == null or not g.V6_FRAMES.has(name) or o.pfx.size() > 220:
		return
	var spec: Array = g.V6_FRAMES[name]
	var frames: int = maxi(1, int(spec[0]))
	var fps: float = maxf(1.0, float(spec[1]))
	var pts: Array = []
	match str(f.get("at", "center")):
		"self":
			pts.append(o.pos)
		"leader":
			pts.append(o.lead_pos())
		"zone":
			pts.append(o.zone_c() if o.has_method("zone_c") else c)
		"hits":
			for e in hits:
				pts.append(e.pos + Vector2(0, -float(e.r) * 0.5))
		_:
			pts.append(c)
	var sc: float = float(f.get("scale", 1.0))
	var fit: float = float(f.get("fit", 0.0))
	sc *= r / fit if fit > 0.0 and r > 0.0 else g.PX
	sc = minf(sc, float(f.get("max_scale", FX_SCALE_MAX)))
	if g.vfx != null and g.vfx._fxc != null:
		g.vfx._fx_census("SC|%s|%.3f" % [name, sc / ArtS.hires_of(g.tex[name])], false)
	var loop: bool = f.has("life") and not f.get("once", false)
	var life: float = float(f.life) if loop else frames / fps
	if f.has("stay"):   # 精英化段：一次性帧条播完停在末帧，共 stay 秒（钉剑插在敌人身上）
		life = maxf(life, float(f.stay))
	var tint: Color = Color.WHITE
	var tv = f.get("tint", [])
	if tv is Array and tv.size() >= 3:
		tint = Color(float(tv[0]), float(tv[1]), float(tv[2]), float(tv[3]) if tv.size() > 3 else 1.0)
	var anc := Vector2(-1, -1)
	var av = f.get("anchor", [])
	if av is Array and av.size() == 2:
		anc = Vector2(float(av[0]), float(av[1]))
	var off := Vector2.ZERO
	var ov = f.get("off", [])
	if ov is Array and ov.size() == 2:
		off = Vector2(float(ov[0]), float(ov[1]))
	if f.get("face_x", false):
		off.x *= float(o.face)
	if f.has("on_sprite") and o.has_method("sprite_point"):   # 10-15：锚到帧条定位点（星熊格挡闪光对准盾心），这一帧没有就照旧
		var spp: Vector2 = o.sprite_point(str(f.on_sprite))
		if spp != Vector2.INF:
			pts = [spp]
			off = Vector2.ZERO   # off 只是找不到定位点时的旧偏移
	if f.has("along"):   # 精英化段：沿出手方向往外放 along × 半径（锥形斩的刀光放在身前）
		off += Vector2.from_angle(ang) * r * float(f.along)
	var dly: float = float(f.get("delay", 0.0))   # 精英化段：delay 秒后才起播（画面计时，不进玩法）
	var rot: float = (ang if f.get("rot", false) else 0.0) + deg_to_rad(float(f.get("ang", 0.0)))
	var layer: String = str(f.get("layer", "over"))
	var spread: float = float(f.get("spread", 0.0)) * r
	var rise: float = float(f.get("rise", 0.0))
	var ease: String = str(f.get("ease", ""))
	var grow: float = float(f.get("grow", FX_GROW))
	if ease != "" and str(f.get("grow_to", "")) == "zone" and o.has_method("zone_c"):
		pts = [o.zone_c()]   # grow_to = zone：从区域中心扩到区域半径（画的时候每帧跟着区域中心 / 半径走）
	var sumk: String = str(f.get("grow_to", "")).substr(7) if ease != "" and str(f.get("grow_to", "")).begins_with("summon:") else ""
	if sumk != "":   # 精英化第 5 批段：grow_to = summon:<种类>，从那个召唤物扩到它的区域半径（画的时候每帧跟着它走）
		var sp: Dictionary = _F().e5_summon(o, sumk)
		if sp.is_empty():
			return
		pts = [sp.pos]
	for p in pts:
		if p == Vector2.INF:
			continue
		for k in int(f.get("n", 1)):
			var q: Vector2 = p + off
			if spread > 0.0:
				var a: float = g.vrng.randf() * TAU
				var d: float = sqrt(g.vrng.randf()) * spread
				q += Vector2(cos(a) * d, sin(a) * d * 0.55)   # 地面椭圆（同区域画法 y × 0.55）
			var angle: float = (c + off - q).angle() if f.get("inward", false) else rot
			var px := {"kind": "strip", "name": name, "pos": q, "life": life, "sc": sc, "col": tint, "ang": angle, "anc": anc, "no_fade": bool(f.get("no_fade", false)),
				"fr": frames, "fps": fps, "loop": loop, "ph": g.vrng.randi_range(0, frames - 1) if loop else 0,
				"floor": layer == "floor", "add": layer == "add", "fit": fit > 0.0}
			if dly > 0.0:
				px["life"] = life + dly
				px["dly"] = dly
			if rise != 0.0:
				px["vel"] = Vector2(0, -rise)
			if ease != "":   # 扩散缓动（§5.6 ease / grow / grow_to / wake，10-13 加）：半径在画的时候按经过时间算，见 fx_draw_grow
				px["life"] = grow
				px["grow"] = grow
				px["ease"] = ease
				px["g0"] = float(f.get("grow0", FX_GROW0))
				px["R"] = r * float(f.get("scale", 1.0))
				px["zmul"] = float(f.get("scale", 1.0))
				px["zone"] = str(f.get("grow_to", "")) == "zone"
				if sumk != "":
					px["sumk"] = sumk
				if str(f.get("play", "")) == "fps":
					px["pfps"] = true
				px["off"] = off
				px["maxs"] = float(f.get("max_scale", FX_SCALE_MAX))
				px["src"] = o
				if f.get("wake", null) is Dictionary:
					px["wake"] = f.wake
			if float(f.get("xfade", 0.0)) > 0.0:
				px["xe"] = f   # 交叉淡入淡出：画的时候乘条目 cond 的平滑权重（fx_xw）
				px["src"] = o
			o.fx(px)


## 画一条 strip 粒子（data_operator._draw_pfx / draw_fx_add 调）。dim：整体透明度（fx_dim）
static func fx_draw(ci, g, f: Dictionary, dim: float) -> void:
	if f.has("grow"):
		fx_draw_grow(ci, g, f, dim)
		return
	if f.has("xe"):
		dim *= fx_xw(f.src, f.xe)
		if dim <= 0.004:
			return
	var el: float = float(f.max) - float(f.life) - float(f.get("dly", 0.0))
	if el < 0.0:
		return   # 精英化段：delay 还没到
	var frames: int = int(f.fr)
	var fr: int
	var a: float = dim
	if f.loop:
		fr = (int(el * float(f.fps)) + int(f.ph)) % frames
		if not f.get("no_fade", false):
			a *= clampf(float(f.life) / maxf(0.01, float(f.max) * 0.3), 0.0, 1.0) * clampf(el / 0.08, 0.0, 1.0)   # 循环件：进场 0.08 秒、最后三成淡出
	else:
		fr = mini(int(f.get("first_frame", 0)) + int(el * float(f.fps)), frames - 1)
	if f.get("slash_material", false):
		a *= clampf(1.0 - (el - float(f.slash_break_at)) / 0.08, 0.0, 1.0)
	if not f.loop:
		a *= _mat_handoff(g, f, el, frames, fr)
	var sc: float = float(f.sc) if f.get("fit", false) or not ("vfx" in g) or g.vfx == null else g.vfx.int_scale(float(f.sc))   # 低分辨率层整数格（docs/138 §10）；按半径拟合的不取整
	fx_frame(ci, g, str(f.name), frames, fr, f.pos, sc, Color(f.col.r, f.col.g, f.col.b, f.col.a * a), f.anc, float(f.ang))


## 帧条的第 fr 帧：sc = 每个 1x 美术像素的世界像素数；anc = 1x 帧内锚点（(-1,-1) = 帧中心），@2x 贴图自动换算（docs/25 §6 的 ×A.hires 规则）
static func fx_frame(ci, g, name: String, frames: int, fr: int, pos: Vector2, sc: float, col: Color, anc := Vector2(-1, -1), ang := 0.0, stretch := 1.0) -> void:
	var tx: Texture2D = g.tex.get(name)
	if tx == null or col.a <= 0.0:
		return
	var h: float = ArtS.hires_of(tx)
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	var an: Vector2 = anc * h if anc.x >= 0.0 else Vector2(fw, fh) / 2.0
	ci.draw_set_transform(pos, ang, Vector2(sc * stretch / h, sc / h))   # stretch：沿朝向拉长（剑气猛冲段，sword_ease.gd）
	ci.draw_texture_rect_region(tx, Rect2(-an, Vector2(fw, fh)), Rect2(fw * (fr % frames), 0, fw, fh), col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- 扩散缓动 / 交叉淡入淡出 / 余波环（docs/61 §5.6，10-13 加；纯画面）
## 用户 10-13「浊心斯卡蒂的声浪的转变是不是也有点僵硬」：小帧条整条放大 4 倍、按灯火硬切两套、扩散匀速且够不到歌域边。
## ease：半径从 grow0 × R 按缓动曲线扩到 R（grow 秒），帧号跟着扩散进度走、每帧按这一帧自身的半径缩放（帧条里的圈不论画多大都正好落在当前半径上）；
## 帧条只作纹理层：随扩散渐淡，放大超过 max_scale 后按 (max_scale / 倍率)² 再淡（颗粒粗的大圈交给程序余波环）；
## wake：程序余波环（顶点色软边环带，合批提交），领头一道正好在当前半径、后面几道各晚 lag 秒，外缘随扩散渐淡。
## xfade：同一组按 cond 二选一的条目（灯火明 / 暗）不再硬切：两条都生成，透明度乘各自 cond 的平滑权重（xfade 秒从 0 到 1）。
const FX_GROW := 0.65        # 扩散时长缺省（秒）

const FX_GROW0 := 0.12       # 起始半径比例缺省

const FX_EASES := ["out", "out2", "linear"]

const FX_WAKE_DEF := {"n": 2, "w": 10.0, "a": 0.5, "lag": 0.09, "sy": 0.55, "col": null}

const FX_WAKE_LIM := {"n": [0, 4], "w": [1.0, 60.0], "a": [0.0, 1.0], "lag": [0.0, 0.5], "sy": [0.1, 1.0]}

static var _fr_r := {}       # 帧条名 → 每帧自身半径（1x 像素，按不透明像素的横向范围量一次缓存）


## 缓动：out = 三次方先快后慢（缺省），out2 = 二次方，linear = 匀速
static func fx_ease(kind: String, t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	match kind:
		"out2":
			return 1.0 - (1.0 - t) * (1.0 - t)
		"linear":
			return t
	return 1.0 - pow(1.0 - t, 3.0)


## 帧条第 fr 帧自身的半径（1x 像素）：不透明像素离帧中心的最大横向距离；量不到（压缩贴图读不出图）时按帧宽一半
static func fx_frame_r(g, name: String, frames: int, fr: int) -> float:
	if not _fr_r.has(name):
		_fr_r[name] = _calc_frame_r(g.tex.get(name), frames)
	var a: Array = _fr_r[name]
	return float(a[fr]) if fr < a.size() else 0.0


## 预热（10-22 网页开局掉帧：第一次放浊心斯卡蒂声浪时这里读回整张帧条逐像素量半径，当帧 100+ ms）：
## 标题页出发后的等待里用同一张贴图（A.tex 缓存，局内 g.tex 就是它）先算好，结果与首用时现算相同
static func warm_frame_r(name: String, tx: Texture2D, frames: int) -> void:
	if tx != null and not _fr_r.has(name):
		_fr_r[name] = _calc_frame_r(tx, frames)


static func _calc_frame_r(tx: Texture2D, frames: int) -> Array:
	var rs: Array = []
	if tx != null:
		var h: float = ArtS.hires_of(tx)
		var fw: int = tx.get_width() / frames
		var img: Image = tx.get_image()
		if img != null and img.is_compressed():
			img = null
		for k in frames:
			var r := fw / 2.0
			if img != null:
				var mn := fw
				var mx := -1
				for x in fw:
					for y in range(0, img.get_height(), 1):
						if img.get_pixel(k * fw + x, y).a > 0.1:
							mn = mini(mn, x)
							mx = maxi(mx, x)
							break
				if mx >= mn:
					r = maxf(fw / 2.0 - mn, mx + 1 - fw / 2.0)
			rs.append(maxf(1.0, r) / h)
	return rs


## 交叉淡入淡出权重：条目 f 的 cond 此刻为真 → 1，假 → 0，按 xfade 秒线性靠拢（只看 g.t，画面状态存在干员的 meta 里，不碰玩法）。
## 同 strip + cond + if_tex 的条目共用一个权重（普攻与回声同一档灯火同进同出）
static func fx_xw(o, f: Dictionary) -> float:
	if o == null or not is_instance_valid(o):
		return 1.0
	var xf: float = float(f.get("xfade", 0.0))
	var tgt: float = 1.0 if fx_on(o, f) else 0.0
	if xf <= 0.0:
		return tgt
	var m: Dictionary = o.get_meta("fx_xw") if o.has_meta("fx_xw") else {}
	if not o.has_meta("fx_xw"):
		o.set_meta("fx_xw", m)
	var key := "%s|%s|%s" % [f.get("strip", ""), f.get("cond", ""), f.get("if_tex", "")]
	var t: float = float(o.g.t)
	if not m.has(key):
		m[key] = [tgt, t]
		return tgt
	var v: Array = m[key]
	var w: float = move_toward(float(v[0]), tgt, maxf(0.0, t - float(v[1])) / xf)
	m[key] = [w, t]
	return w


## 生成时的取舍：带 xfade 的条目只看 if_tex（cond 交给画的时候的权重），并先把权重推到此刻；其余同 fx_on
static func fx_on_spawn(o, f: Dictionary) -> bool:
	if float(f.get("xfade", 0.0)) <= 0.0 or not f.has("cond"):
		return fx_on(o, f)
	var it = f.get("if_tex", "")
	if it is String and it != "":
		var neg: bool = it.begins_with("!")
		if (o.g.tex.get(it.substr(1) if neg else it) != null) == neg:
			return false
	fx_xw(o, f)   # 先把权重推到此刻
	return true   # 两档都生成：扩散途中跨阈值时同一圈声浪也能平滑换图（权重为 0 的那条画的时候直接跳过）


## 扩散缓动粒子（fx_spawn 写了 grow）：帧条纹理层 + 程序余波环
static func fx_draw_grow(ci, g, f: Dictionary, dim: float) -> void:
	var o = f.get("src")
	var el: float = float(f.max) - float(f.life)
	var T: float = maxf(0.05, float(f.grow))
	var t: float = clampf(el / T, 0.0, 1.0)
	var a: float = dim * clampf(el / 0.06, 0.0, 1.0)
	if f.has("xe"):
		a *= fx_xw(o, f.xe)
	if a <= 0.004:
		return
	var c: Vector2 = f.pos
	var R: float = float(f.R)
	if f.zone and o != null and is_instance_valid(o) and o.has_method("zone_c"):
		var zc: Vector2 = o.zone_c()
		if zc != Vector2.INF:
			c = zc + f.off
			R = float(o.zr) * float(f.zmul)
	elif f.has("sumk") and o != null and is_instance_valid(o):   # 精英化第 5 批段：跟着召唤物与它的区域半径走（召唤物没了就停在最后的位置）
		var sp: Dictionary = _F().e5_summon(o, str(f.sumk))
		if not sp.is_empty():
			c = sp.pos + f.off
			R = float(sp.get("zr", R)) * float(f.zmul)
	var e: float = fx_ease(str(f.ease), t)
	var g0: float = float(f.g0)
	var rad: float = R * lerpf(g0, 1.0, e)
	# 纹理层：帧号跟扩散进度走（帧 0 多是起爆小点，帧数 ≥ 3 时从帧 1 起），且不选比原尺寸（g.PX）还要放大的小帧——
	# 当前半径够大时直接跳到自身半径 × PX ≤ 当前半径的最后一帧；每帧按自身半径缩放到当前半径
	var frames: int = int(f.fr)
	var fr: int = clampi(int(e * frames), 1 if frames >= 3 else 0, frames - 1)
	if f.get("pfps", false):   # 精英化第 5 批段：play = fps，帧号按帧条自己的 fps 播（回声环一帧比一帧疏，不跳帧）
		fr = mini(int(el * float(f.fps)), frames - 1)
	else:
		for k in range(frames - 1, fr, -1):
			if fx_frame_r(g, str(f.name), frames, k) * g.PX <= rad:
				fr = k
				break
	var rf: float = fx_frame_r(g, str(f.name), frames, fr)
	if rf > 0.0:
		var sc: float = rad / rf
		var ta: float = a * pow(1.0 - t, 1.3)
		var mxs: float = float(f.maxs)
		if sc > mxs:
			ta *= pow(mxs / sc, 2.0)
		if ta > 0.004:
			fx_frame(ci, g, str(f.name), frames, fr, c, sc, Color(f.col.r, f.col.g, f.col.b, f.col.a * ta), f.anc, float(f.ang))
	if f.has("wake"):
		fx_wake(ci, f.wake, c, R, g0, str(f.ease), el, T, a, f.col)


## 程序余波环：n 道软边环带（透视椭圆 y × sy），第 i 道晚 i × lag 秒起步、同一缓动扩到 R；环带宽 w（随扩散略展宽），
## 透明度 a × (1 - 进度)^1.4 × 越往后越淡；颜色 col（缺省取条目 tint 的 rgb）。全部顶点色三角形攒成一组：合批画布走 add_tris，否则直接提交
static func fx_wake(ci, wk: Dictionary, c: Vector2, R: float, g0: float, ease: String, el: float, T: float, a: float, tint: Color) -> void:
	var n: int = int(wk.get("n", FX_WAKE_DEF.n))
	var w: float = float(wk.get("w", FX_WAKE_DEF.w))
	var wa: float = float(wk.get("a", FX_WAKE_DEF.a)) * a
	var lag: float = float(wk.get("lag", FX_WAKE_DEF.lag))
	var sy: float = float(wk.get("sy", FX_WAKE_DEF.sy))
	var cv = wk.get("col", null)
	var col := Color(tint.r, tint.g, tint.b)
	if cv is Array and cv.size() >= 3:
		col = Color(float(cv[0]), float(cv[1]), float(cv[2]))
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var seg: int = clampi(int(R / 5.0), 32, 72)
	for i in n:
		var ti: float = clampf((el - lag * i) / T, 0.0, 1.0)
		if ti <= 0.0:
			continue
		var ri: float = R * lerpf(g0, 1.0, fx_ease(ease, ti))
		var wi: float = w * (0.7 + 0.6 * ti) * (1.0 - 0.2 * i)
		var ai: float = wa * pow(1.0 - ti, 1.4) * (1.0 - 0.3 * i) * clampf((el - lag * i) / 0.05, 0.0, 1.0)
		if ai <= 0.004:
			continue
		var cin := Color(col.r, col.g, col.b, 0.0)
		var cpk := Color(minf(col.r * 1.15, 1.0), minf(col.g * 1.1, 1.0), minf(col.b * 1.1, 1.0), ai)
		_wake_band(pts, cols, idx, c, maxf(0.0, ri - wi), ri, cin, cpk, sy, seg)        # 内侧拖尾：透明 → 峰值
		_wake_band(pts, cols, idx, c, ri, ri + wi * 0.35, cpk, cin, sy, seg)             # 外缘：峰值 → 透明（窄，前沿清楚）
	if idx.is_empty():
		return
	if ci != null and ci.has_method("add_tris"):
		ci.add_tris(pts, cols, idx)
	else:
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)


static func _wake_band(pts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, c: Vector2, r0: float, r1: float, c0: Color, c1: Color, sy: float, seg: int) -> void:
	var base: int = pts.size()
	for q in seg:
		var d := Vector2.from_angle(q * TAU / seg)
		pts.append(c + Vector2(d.x * r0, d.y * r0 * sy))
		pts.append(c + Vector2(d.x * r1, d.y * r1 * sy))
		cols.append(c0)
		cols.append(c1)
	for q in seg:
		var a0: int = base + q * 2
		var a1: int = base + ((q + 1) % seg) * 2
		idx.append_array([a0, a0 + 1, a1 + 1, a0, a1 + 1, a1])


## 常驻跟随条目：贴身层（behind / front）、程序漩涡（vortex）或常驻跟随帧条（hold），积木生效期间一直画、退出淡出
static func fx_is_hold(f) -> bool:
	return f is Dictionary and (str(f.get("layer", "")) in FX_BODY or f.has("vortex") or _hold(f) or f.has("aura_ring") or f.has("outline"))


## 条目是不是常驻跟随帧条（hold: true；写成非布尔时按 false，校验另报错）
static func _hold(f: Dictionary) -> bool:
	var h = f.get("hold", false)
	return h is bool and h


## 条目这一刻画不画：cond（§1.3）+ if_tex（"fx_x" = 有这条贴图才画；"!fx_x" = 缺这条贴图才画，程序回退用；10-12 加）
static func fx_on(o, f: Dictionary) -> bool:
	if not cond_true(o, f.get("cond", _ED)):
		return false
	var it = f.get("if_tex", "")
	if it is String and it != "":
		var neg: bool = it.begins_with("!")
		var has: bool = o.g.tex.get(it.substr(1) if neg else it) != null
		return has != neg
	return true


## 常驻跟随条目的淡入 / 淡出秒数 Vector2(in, out)：条目 fade（数字 = 进出同长；[进, 出]）优先，
## 缺省：贴身层 (0, FX_BODY_FADE)，漩涡 (0.5, FX_VORTEX_FADE)，hold 帧条 (FX_HOLD_FADE, FX_HOLD_FADE)
static func fx_fade_io(f: Dictionary) -> Vector2:
	var d := Vector2(FX_HOLD_FADE, FX_HOLD_FADE)
	if f.has("vortex"):
		d = Vector2(0.5, FX_VORTEX_FADE)
	elif str(f.get("layer", "")) in FX_BODY:
		d = Vector2(0.0, FX_BODY_FADE)
	var v = f.get("fade", null)
	if v is Array and v.size() == 2:
		d = Vector2(float(v[0]), float(v[1]))
	elif v is int or v is float:
		d = Vector2(float(v), float(v))
	return d


## 积木退出后贴身层记录保留多久（= 各常驻跟随条目淡出秒数的最大值）
static func fx_hold_out(entries) -> float:
	var m := 0.0
	if entries is Array:
		for f in entries:
			if fx_is_hold(f):
				m = maxf(m, fx_fade_io(f).y)
	return m if m > 0.0 else FX_BODY_FADE


## 条目的进出透明度：e 是贴身层记录 {el = 生效秒数, fade = 退出后剩余秒数（< 0 = 生效中）}
static func fx_hold_alpha(f: Dictionary, e: Dictionary) -> float:
	var io := fx_fade_io(f)
	var a: float = 1.0 if io.x <= 0.0 else clampf(float(e.el) / io.x, 0.0, 1.0)
	if float(e.fade) >= 0.0:
		a *= clampf(float(e.fade) / io.y, 0.0, 1.0) if io.y > 0.0 else 0.0
	return a


## 常驻跟随帧条（hold: true）：积木生效期间在 at 点循环播（帧号 = floor(生效秒数 × fps) % 帧数），
## 写了 fit 时每帧按当前区域半径缩放（每个 1x 像素 = r / fit × scale，夹到 max_scale），区域变大变小即时跟上；进出按 fade 淡入淡出。
## layer：ground = 地砖之上、溟痕 / 地面预警 / 掉落之下（data_operator.draw_ground_fx）；floor = 区域椭圆层（draw_auras）；add = 加色层
static func fx_hold_strips(ci, o, e: Dictionary, layer: String, c_zone: Vector2, r_zone: float) -> void:
	var g = o.g
	for f in e.b.fx:
		if not (f is Dictionary) or not _hold(f) or str(f.get("layer", "floor")) != layer or not fx_on(o, f):
			continue
		var name: String = str(f.get("strip", ""))
		if g.tex.get(name) == null or not g.V6_FRAMES.has(name):
			continue
		var spec: Array = g.V6_FRAMES[name]
		var frames: int = maxi(1, int(spec[0]))
		var tv = f.get("tint", [])
		var col := Color.WHITE
		if tv is Array and tv.size() >= 3:
			col = Color(float(tv[0]), float(tv[1]), float(tv[2]), float(tv[3]) if tv.size() > 3 else 1.0)
		col.a *= fx_hold_alpha(f, e) * float(g.world.fx_dim)
		if col.a <= 0.004:
			continue
		if str(f.get("flash", "")) == "fire":   # 精英化段：本干员每次普攻出手提亮一下（0.25 秒衰减）
			var k: float = clampf(1.0 - (float(g.t) - float(o.el.get("fire_t", -99.0))) / 0.25, 0.0, 1.0)
			col = Color(col.r * (1.0 + 0.9 * k), col.g * (1.0 + 0.9 * k), col.b * (1.0 + 0.6 * k), minf(1.0, col.a * (1.0 + 0.5 * k)))
		var cs: Array = [c_zone]
		match str(f.get("at", "zone")):
			"self":
				cs = [o.pos]
			"leader":
				cs = [o.lead_pos()]
			"members":   # 精英化段：光环（aura.*）的受益者，每人头顶一个
				cs = []
				for m in aura_members(o, str(e.b.get("scope", "others"))):
					cs.append(m.pos)
		var ov = f.get("off", [])
		var off: Vector2 = Vector2(float(ov[0]), float(ov[1])) if ov is Array and ov.size() == 2 else Vector2.ZERO
		if f.get("face_x", false):
			off.x *= float(o.face)
		var sc: float = float(f.get("scale", 1.0))
		var fit: float = float(f.get("fit", 0.0))
		sc *= r_zone / fit if fit > 0.0 and r_zone > 0.0 else g.PX
		sc = minf(sc, float(f.get("max_scale", FX_SCALE_MAX)))
		var av = f.get("anchor", [])
		var anc: Vector2 = Vector2(float(av[0]), float(av[1])) if av is Array and av.size() == 2 else Vector2(-1, -1)
		for c in cs:
			if c == Vector2.INF:
				continue
			fx_frame(ci, g, name, frames, int(floor(float(e.el) * float(spec[1]))) % frames, c + off, sc, col, anc, deg_to_rad(float(f.get("ang", 0.0))))


## 积木的 fx 里有没有常驻跟随条目（贴身层 / 漩涡）
static func fx_has_body(entries) -> bool:
	if entries is Array:
		for f in entries:
			if fx_is_hold(f):
				return true
	return false


## fx 条目里有没有一条帧条的贴图在（没有时调用方画程序底）
static func fx_any_tex(o, entries) -> bool:
	if entries is Array:
		for f in entries:
			if f is Dictionary and o.g.tex.get(str(f.get("strip", ""))) != null and fx_on(o, f):
				return true
	return false


## 积木的 fx 里有没有漩涡条目（退出淡出用 FX_VORTEX_FADE）
static func fx_has_vortex(entries) -> bool:
	if entries is Array:
		for f in entries:
			if f is Dictionary and f.has("vortex"):
				return true
	return false


## 帧条后半段换颗粒（docs/138 §11，fx_grains.MAT_HANDOFF）：播到交接比例那一刻从当前帧迸出材质颗粒，之后返回帧条的淡出系数；
## 颗粒没生成（材质关 / 预算满 / 低画质）就返回 1，帧条照原样播完。只在画的时候算，随机只走 g.vrng
static func _mat_handoff(g, f: Dictionary, el: float, frames: int, fr: int) -> float:
	var grains = g.optical.grains if "optical" in g and g.optical != null else null
	if grains == null or f.get("mat_skip", false) or not grains.MAT_HANDOFF.has(str(f.name)):
		return 1.0
	var at: float = float(grains.MAT_HANDOFF[str(f.name)]) * float(frames) / maxf(1.0, float(f.fps))
	if not f.has("mat_t"):
		if el < at:
			return 1.0
		f["mat_t"] = el
		f["mat_ok"] = false
		var tx: Texture2D = g.tex.get(str(f.name))
		if tx != null:
			var h: float = ArtS.hires_of(tx)
			var fw: float = float(tx.get_width()) / float(frames)
			var an: Vector2 = f.anc * h if f.anc.x >= 0.0 else Vector2(fw, tx.get_height()) / 2.0
			f["mat_ok"] = grains.material_burst(str(f.name), tx, frames, f.pos, float(f.ang), float(f.sc) / h, an, false, f.col, fr)
	if not f.mat_ok:
		return 1.0
	return clampf(1.0 - (el - float(f.mat_t)) / 0.08, 0.0, 1.0)
