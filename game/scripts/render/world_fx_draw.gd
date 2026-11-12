## 世界层 g.fx 特效绘制（world._draw_fx 的分派 match 与它专用的小函数）。docs/286 §4 第三批从 render/world.gd 原样拆出，行为不变。
## 全部是 static func，第一个参数 wv = world（render/world.gd 实例）；读写的成员都经 wv.、常量经 W.。画面随机只用 g.vrng，消耗次序与拆分前相同。
extends RefCounted

const W = preload("res://scripts/render/world.gd")
const LaserDraw = preload("res://scripts/render/laser_draw.gd")
const FinalAttackDraw = preload("res://scripts/render/boss_attack_draw.gd")
const BossBeam = preload("res://scripts/render/boss_beam.gd")   # Boss 改版样板：Kanpelle 光束、骑士寒气圈 / 寒冷条（docs/142b）
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const Bal = preload("res://scripts/core/balance.gd")
const LateRead = preload("res://scripts/render/late_read.gd")   # 后期可读性第一批（docs/247，render/late_read）
const Dc = preload("res://scripts/render/declutter.gd")   # 后期降噪预设（render/declutter）
const GroundCrack = preload("res://scripts/render/ground_crack.gd")
const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
## 灯标驱散环（11-08 用户 iPhone「很粗的白 / 淡紫椭圆圈、锯齿明显」，beacon/sweep_px = 1）：按美术像素格逐格画的贴地椭圆，
## 外沿一格灯火暖黄、往里一格溟痕淡紫（都在 0–1 内，网页没有 HDR 也不会截成白色），每 7 格按哈希断开约两成，不是整齐几何圆；
## 暖黄每 3 格一格进光学发光层。颜色取灯标点燃暖光（vfx beacon glow 1.0 / 0.86 / 0.6）与溟痕紫
const SWEEP_FRONT := Color("#ffd98a")
const SWEEP_BACK := Color("#8f62c8")


static func _draw_fx(wv: W) -> void:
	var g: Game = wv.g
	if not wv._dbg_foe and not wv._dbg_foefx:
		FinalAttackDraw.draw(g, true)
	wv.bfx_grains = BossBeam.grains(g)
	# 友方火花绘制预算（render/declutter spark_budget；缺省不限）：超出时跳过最早的（快淡完的），只影响绘制
	var skip_sparks := 0
	if wv.spark_left < (1 << 29):
		var ns := 0
		for f in g.fx:
			if f.kind == "spark" and not f.get("enemy", false):
				ns += 1
		skip_sparks = maxi(0, ns - wv.spark_left)
	for f in g.fx:
		if f.life <= 0.0 or f.get("ground", false):
			continue   # ground：地面层敌方特效（奠基者地裂）已在 _draw_ground_foe_fx 画过；到期还没被 _cleanup 回收的特效不画：最终 Boss 击破的慢动作（victory_flow）走 g.vfx.update 但不跑 game._update/_cleanup，
			# 到期特效会一直留在 g.fx 里；"sprite" 类按已播时间取帧，life ≤ 0 后会被夹在末帧一直画（骑士死亡原地留下冰晶/冰砖残留）
		var a: float = clamp(f.life / f.max, 0.0, 1.0)
		var foe: bool = f.get("enemy", false) or W.FOE_KINDS.has(f.kind)
		if ((wv._dbg_foe or wv._dbg_foefx) and foe) or (wv._dbg_friend and not foe and not W.AMB_KINDS.has(f.kind)) or (wv._dbg_amb and W.AMB_KINDS.has(f.kind)):
			continue   # --clutterdbg 量测：这一层不画
		if wv._dbg_opmask and not foe and f.has("sop") and Dc.mute_op(str(f.sop), f.get("lead", false)):
			continue   # 后期特效分账：该干员出手生成的帧条不画
		if wv.bfx_grains != null and f.has("bfx") and W.BFX_KINDS.has(f.kind):
			# Boss 结算特效（telegraph.warn_resolve 打的 bfx = 专属色）：第一帧迸出颗粒，矢量形压成半透明的底（起手 = 预警、爆发 = 颗粒、消散 = 颗粒飘散）
			if not f.has("bg"):
				f["bg"] = true
				_bfx_grains(wv, f)
			a *= W.BFX_DIM
		var fdim: float = 1.0 if f.get("enemy", false) else (wv.deco_dim if wv.lr_v3 and W.DECO_KINDS.has(f.kind) else wv.fx_dim)   # 敌方特效不降噪（docs/48 ③）；V3：只有装饰件吃降噪
		if fdim < 1.0 and W.DIM_KINDS.has(f.kind):
			a *= fdim
		if skip_sparks > 0 and f.kind == "spark" and not f.get("enemy", false):
			skip_sparks -= 1
			continue
		if f.kind == "kp_beam":
			BossBeam.draw(g, f)   # Boss 激光（Kanpelle 帧条，docs/142b §8.5）；缺图不画（结算伤害不受影响）
			wv.bulfx.beam_px(f, g.vfx.boss_color(str(f.get("boss", ""))), 6.0 * float(f.get("k", 2.0)))   # 光束颗粒（docs/206 §3）
			continue
		if f.kind == "beam" or f.kind == "bbeam" or f.kind == "tracer":
			LaserDraw.draw(g, f, a)   # 激光 A 像素光束（docs/138 §12；旧开关 fx/laser_style 与原画法已删）
			if f.kind == "bbeam" or (f.kind == "tracer" and f.get("enemy", false)):
				wv.bulfx.beam_px(f, LaserDraw._unit(f.get("col", Color.WHITE)), LaserDraw._base_w(f) * 0.5)   # Boss 光束颗粒（docs/206 §3）
			continue
		match f.kind:
			"warp_out":   # 队友就地解散（squad._leave_fx，11-02 取代向上跳出屏幕）：脚下光圈收拢 + 身体泛青白、像素碎散淡出
				var wt: float = (f.max - f.life) / f.max
				var wc: Color = f.col
				g.draw_set_transform(f.pos, 0.0, Vector2(1.0, wv.ground_y()))
				g.draw_arc(Vector2.ZERO, lerpf(30.0, 4.0, wt) * g.PX * 0.5, 0.0, TAU, 32, Color(wc.r * 1.3, wc.g * 1.3, wc.b * 1.3, 0.85 * (1.0 - wt)), 2.0)
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				wv.draw_sprite_at(f.pos, f.st.flip, Color(1.0 + 0.6 * wt, 1.0 + 0.7 * wt, 1.0 + 0.8 * wt, 1.0 - wt), f.st.frame, f.st.tex, f.st.hf, f.foot_off)
				for q in 16:   # 像素碎散：身体范围里 16 个 2 像素格，向外 / 略向上散开淡出（按 seed 定位，不抽随机数）
					var h: int = (int(f.seed) * 131 + q * 977) & 1023
					var base := Vector2(float(h % 21) - 10.0, -float((h >> 3) % 34) - 4.0) * g.PX * 0.5
					var drift := Vector2(base.x * 0.9, -6.0 - float(q % 5) * 2.0) * g.PX * 0.5 * wt
					var pp: Vector2 = ((f.pos + base * 2.0 + drift) / g.PX).floor() * g.PX
					g.draw_rect(Rect2(pp, Vector2(g.PX, g.PX)), Color(wc.r * 1.4, wc.g * 1.4, wc.b * 1.4, (1.0 - wt) * (0.6 + 0.4 * float(q % 2))))
			"leave_jump":   # 旧：原地一蹲后向上跳出屏幕（squad/deploy_exit = 0 对照用，10-22）
				var jt: float = (f.max - f.life) / f.max
				var jy: float = 2.0 * g.PX if jt < 0.12 else -pow((jt - 0.12) / 0.88, 1.6) * (wv.view_rect(0.0).size.y + 80.0 * g.PX)
				wv.draw_sprite_at(f.pos + Vector2(0, jy), f.st.flip, Color.WHITE, f.st.frame, f.st.tex, f.st.hf, f.foot_off)
			"frost":
				# 寒冰领域：淡蓝地面 + 旋转冰纹（地面椭圆与判定一致，ground_y，docs/48 ①）
				var fa: float = minf(1.0, f.life / 0.6) * 0.9
				g.wcv.draw_set_transform(f.pos, 0.0, Vector2(1.0, wv.ground_y()))
				g.wcv.draw_circle(Vector2.ZERO, f.r, Color(0.5, 0.8, 1.2, 0.14 * fa))
				g.wcv.draw_arc(Vector2.ZERO, f.r, 0.0, TAU, 48, Color(0.8, 1.2, 1.8, 0.6 * fa), 2.0)
				for q in 6:
					var qa: float = g.t * 0.6 + TAU * q / 6.0
					g.wcv.draw_line(Vector2.from_angle(qa) * f.r * 0.2, Vector2.from_angle(qa) * f.r * 0.95, Color(0.9, 1.3, 1.9, 0.25 * fa), 2.0)
				g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"frost_track":
				# 骑士冰线：连续的碎裂冰脊与亮芯，和追击预警共用相同方向。
				var side: Vector2 = (f.b - f.a).orthogonal().normalized()
				var spine := PackedVector2Array()
				for q in 12:
					var u: float = float(q) / 11.0
					spine.append(f.a.lerp(f.b, u) + side * sin(u * 47.0) * 5.0)
				g.wcv.draw_polyline(spine, Color(0.06, 0.2, 0.32, 0.8 * a), 14.0)
				g.wcv.draw_polyline(spine, Color(0.55, 1.2, 1.65, 0.85 * a), 5.0)
				g.wcv.draw_polyline(spine, Color(2.0, 2.4, 2.6, 0.9 * a), 1.5)
				for q in 9:
					var u: float = (float(q) + 0.5) / 9.0
					var at: Vector2 = f.a.lerp(f.b, u)
					var reach: float = 10.0 + float(q % 3) * 4.0
					g.wcv.draw_line(at, at + side * reach * (1.0 if q % 2 == 0 else -1.0), Color(0.8, 1.4, 1.9, 0.8 * a), 2.0)
			"frost_step":
				# 骑士冲锋脚下的冰霜拖尾（10-27 打磨）：不再画一串圆斑，改为 2 像素格的霜点 + 一道短冰裂，按格冷却变暗（白 → 青 → 暗蓝）
				var fp: Vector2 = ((f.pos as Vector2) * 0.5).floor() * 2.0
				var fk: int = int(absf(fp.x) * 0.5 + absf(fp.y) * 1.5)
				var fcol := Color(0.85, 0.97, 1.0) if a > 0.75 else (Color(0.5, 0.78, 0.92) if a > 0.4 else Color(0.2, 0.34, 0.5))
				for q in 7:
					var h: int = (fk * 73 + q * 977) & 1023
					var off := Vector2(float(h % 15) - 7.0, float((h >> 4) % 7) - 3.0) * 2.0
					g.wcv.draw_rect(Rect2(fp + (off * 0.5).floor() * 2.0, Vector2(2, 2)), Color(fcol.r, fcol.g, fcol.b, 0.75 * a))
				g.wcv.draw_line(fp + Vector2(-8, 2), fp + Vector2(0, -2), Color(0.45, 0.68, 0.82, 0.5 * a), 2.0)
				g.wcv.draw_line(fp + Vector2(0, -2), fp + Vector2(6, 0), Color(0.45, 0.68, 0.82, 0.5 * a), 2.0)
			"lead_mark":
				# 队长命中记号（vfx.lead_mark，docs/139 §11）：敌人身上四个像素角标（暖白），跟着敌人走；前 70% 寿命满亮不闪，之后两阶熄灭
				var me = f.get("e")
				var mp: Vector2 = f.pos
				if me is Dictionary and not me.get("dead", false):
					mp = (me.pos as Vector2) + Vector2(0, -float(me.get("r", 12.0)) * 0.6)
				var mq: float = 1.0 if a > 0.3 else (0.66 if a > 0.15 else 0.33)
				var mr: float = clampf(float(f.get("r", 12.0)) * 0.8 + 4.0, 12.0, 24.0) * (1.25 if wv.lead_lv >= 2 else 1.0)
				var arm: float = 6.0 if wv.lead_lv < 1 else (9.0 if wv.lead_lv == 1 else 11.0)
				mp = (mp / 2.0).round() * 2.0
				for sx in [-1.0, 1.0]:
					for sy in [-1.0, 1.0]:
						var cn: Vector2 = mp + Vector2(sx * mr, sy * mr)
						g.wcv.draw_line(cn, cn - Vector2(sx * (arm + 1.0), 0), Color(0.05, 0.04, 0.03, 0.8 * mq), 4.0)
						g.wcv.draw_line(cn, cn - Vector2(0, sy * (arm + 1.0)), Color(0.05, 0.04, 0.03, 0.8 * mq), 4.0)
						g.wcv.draw_line(cn, cn - Vector2(sx * arm, 0), Color(1.0, 0.82, 0.5, mq), 2.0)   # 琥珀白（不过 1，免得被截成纯白）
						g.wcv.draw_line(cn, cn - Vector2(0, sy * arm), Color(1.0, 0.82, 0.5, mq), 2.0)
			"hstar":
				# 命中星（vfx._tier_fx）：中档 4 臂、重档 8 臂；臂长随寿命先长后缩，2 px 线 + 白芯，三阶跳着消失
				var hq: float = ceilf(a * 3.0) / 3.0 * float(f.get("ka", 1.0))   # ka：队友命中压透明度（docs/139 §10）
				var hl: float = float(f.r) * (0.6 + 0.4 * sin((1.0 - a) * PI))
				var hc: Color = f.col
				for q in int(f.n):
					var dv := Vector2.from_angle(TAU * q / float(f.n)) * (hl if q % 2 == 0 else hl * 0.6)
					g.wcv.draw_line(f.pos, f.pos + dv, Color(hc.r * 1.4, hc.g * 1.4, hc.b * 1.4, hq), 2.0)
				g.wcv.draw_rect(Rect2(f.pos - Vector2(2, 2), Vector2(4, 4)), Color(1.8, 1.8, 1.8, hq))
			"marc":
				# 近战刀光（vfx.melee_arc，10-24 用户嫌「沿判定圈的细弧像雷达」改样）：贴着武器的月牙——中间厚两头尖，
				# 半径 = 判定半径 × fx/melee_arc_reach（0.7，贴近身体），扫过角度最多 fx/melee_arc_span（105°）；
				# 判定扇形更宽 / 360° 时只画命中一侧（hit_react 把中心转到第一个被打中的敌人方向）。
				# 三阶硬边：外沿暗带 → 干员本色 → 靠外缘的亮芯（重档加白芯）；厚度按命中档（轻 / 中 / 重）。
				# 跟着挥刀走：前端在前 55% 寿命里扫到终点，尾端从 35% 起追上；位置按干员当前脚底 + 出手时偏移
				var tr: int = int(f.tier)
				var aq: float = ceilf(a * 3.0) / 3.0
				var tk: float = [0.0, 0.8, 1.0, 1.25][tr]   # 厚度按命中档
				var kb: float = [0.0, 1.0, 1.25, 1.6][tr]
				var full: bool = float(f.half) >= PI - 0.01
				var ap: Vector2 = f.pos
				var aop = g.squad.get_op(str(f.get("op", ""))) if g.squad != null else null
				if aop != null and aop.pos != Vector2.INF:
					ap = aop.pos + f.get("off", Vector2.ZERO)
				var rc: float = maxf(18.0, float(f.r) * Bal.v("fx/melee_arc_reach", 0.7))
				var span: float = minf(float(f.half) * 2.0, deg_to_rad(Bal.v("fx/melee_arc_span", 105.0)))
				var sd: float = float(f.get("sdir", 1.0))
				var s0: float = float(f.ang) - span * 0.5 * sd   # 挥刀起点（以刀光中心方向对称）
				# 10-24 用户「还不够像刀光」：厚月牙（厚度 ≈ 半径 30%）、前粗后尖（彗星形）、外沿白刃 → 本色 → 内沿暗边；
				# 前 25% 寿命里一下扫满（拖影帧），之后尾端从起点吃回去；外侧 2–3 道速度线，刀尖迸几颗火星
				var tw: float = clampf(rc * 0.3, 7.0, 26.0) * tk
				var pr: float = 1.0 - a
				var hd: float = clampf(pr / 0.25, 0.0, 1.0)
				var tl: float = clampf((pr - 0.25) / 0.75, 0.0, 1.0)
				var cc: Color = f.col
				if aop != null and aop.is_leader and (wv.lead_boost != 1.0 or wv.lead_tint > 0.0):
					cc = wv.lead_col(cc)   # 队长刀光：提亮 / 暖色（docs/139 §11）
				if wv.mate_on and aop != null and not aop.is_leader:
					cc = wv.mate_col(cc)   # 队友刀光：去饱和、压透明度（颗粒走 cc.a，docs/139 §10）
					cc.a = wv.mate_dim
					aq *= wv.mate_dim
				var gr = g.optical.grains if g.optical != null else null
				if gr != null and gr.on() and not gr.off and hd > 0.0:
					# 刀光第四版（docs/136「slash」粒子模板）：月牙本体由像素颗粒在这一帧扫过的那一段上生成，前沿只留一道热白细线
					_marc_grains(wv, f, gr, ap, rc, tw, s0, sd * span, hd, cc, kb, aq)
				elif hd - tl > 0.02:
					var sw: float = sd * span
					_crescent(wv, ap, rc + 1.0, s0, sw, tl, hd, tw + 2.0, Color(cc.r * 0.35, cc.g * 0.35, cc.b * 0.4, 0.75 * aq), 1.0)   # 暗边（内沿收边）
					_crescent(wv, ap, rc, s0, sw, tl, hd, tw, Color(cc.r * kb, cc.g * kb, cc.b * kb, aq), 1.0)   # 本色刀身
					_crescent(wv, ap, rc, s0, sw, tl, hd, tw * 0.5, Color(minf(1.6, cc.r * kb * 1.4 + 0.4), minf(1.6, cc.g * kb * 1.4 + 0.4), minf(1.6, cc.b * kb * 1.4 + 0.4), aq), 1.0)   # 亮带
					_crescent(wv, ap, rc, s0, sw, tl, hd, maxf(2.0, tw * 0.18), Color(1.9, 1.9, 1.9, aq), 1.0)   # 白刃（外沿）
					for q in (2 if tr < 3 else 3):   # 速度线：外沿外侧几道短细线，越往外越短
						var lr: float = rc + 4.0 + 4.0 * q
						var lu0: float = maxf(tl, hd - 0.45 + 0.12 * q)
						if hd - lu0 > 0.05:
							g.wcv.draw_arc(ap, lr, minf(s0 + sw * lu0, s0 + sw * hd), maxf(s0 + sw * lu0, s0 + sw * hd), 8, Color(cc.r * kb + 0.3, cc.g * kb + 0.3, cc.b * kb + 0.3, 0.55 * aq), 2.0)
					if hd < 1.0 or pr < 0.4:
						var tip: Vector2 = ap + Vector2.from_angle(s0 + sw * hd) * (rc - tw * 0.3)
						for q in 3:   # 刀尖火星（2 px，确定性摆位，不用随机数）
							var sv := Vector2.from_angle(s0 + sw * hd + sd * (0.6 + 0.5 * q)) * (4.0 + 5.0 * q)
							g.wcv.draw_rect(Rect2((tip + sv).round(), Vector2(2, 2)), Color(1.8, 1.8, 1.8, aq))
				var a0: float = 0.0 if full else float(f.ang) - float(f.half)
				var a1: float = TAU if full else float(f.ang) + float(f.half)
				if g.vfx.arc_dbg < 0:
					g.vfx.arc_dbg = 1 if Cfg.dev_args().has("--arcdbg") else 0
				if g.vfx.arc_dbg == 1:
					g.wcv.draw_arc(f.pos, f.r, 0.0, TAU, 64, Color(1, 1, 1, 0.5), 1.0)   # 判定圈（核对，画在出手那一刻的判定原点）
					if not full:
						g.wcv.draw_line(f.pos, f.pos + Vector2.from_angle(a0) * float(f.r), Color(1, 1, 0.3, 0.7), 1.0)
						g.wcv.draw_line(f.pos, f.pos + Vector2.from_angle(a1) * float(f.r), Color(1, 1, 0.3, 0.7), 1.0)
			"ring":
				# op_hit：干员攻击 / 技能命中的装饰环（水月），10-13 用户删、不画；其余（敌方、拾取、藏品……）照画
				if f.get("op_hit", false):
					continue
				if f.get("enemy", false) and Bal.v("render/foe_ring_fx", 1.0) <= 0.0:
					continue   # docs/139 §8：敌方结算后的装饰环（伤害已结算，不是预警）不画
				var rr: float = f.r * (1.15 - a * 0.3)
				g.wcv.draw_arc(f.pos, rr, 0.0, TAU, 28, Color(f.col.r, f.col.g, f.col.b, a * 0.9), 4.0)
				g.wcv.draw_arc(f.pos, rr - 6.0, 0.0, TAU, 28, Color(f.col.r, f.col.g, f.col.b, a * 0.35), 2.0)
			"spark":
				g.wcv.draw_rect(Rect2(f.pos.round(), Vector2(f.sz, f.sz)), Color(f.col.r, f.col.g, f.col.b, a))
			"mote":
				# 光尘（docs/54）：进无贴图批，循环后随 tb_flush 一次提交；末段缩小淡出
				if g.vfx.p2:
					if f.get("em", false):
						# 余烬帧条 fx_ember（8×8 × 4：亮 → 暗红），按剩余寿命取帧，颜色照 mote 调制（docs/54 §6）
						var efr: int = clampi(int((1.0 - a) * 4.0), 0, 3)
						g.vfx.spr_rot("fx_ember", efr, f.pos, 0.0, Game.PX * f.sz * 0.5, Color(f.col.r, f.col.g, f.col.b, f.col.a))
						continue
					var mp: Vector2 = f.pos.round()
					var ms: float = f.sz * (0.5 + 0.5 * minf(1.0, a * 2.0))
					wv.tb_quad(mp, mp + Vector2(ms, 0), mp + Vector2(ms, ms), mp + Vector2(0, ms), Color(f.col.r, f.col.g, f.col.b, f.col.a * minf(1.0, a * 1.5)))
			"mire_recoil":
				# 灯标点燃时被清掉的溟痕退散（docs/54）：每片一圈紫环向中心收缩、深色底渐隐，再一道从灯标推出去的淡光弧。
				# 10-26：每片带延迟 c[2]（自灯标向外扫开），各自在 pd 秒里播完；sweep_r > 0 时再画一道从中心扫到圈边的驱散环
				var el: float = f.max - f.life
				var pd: float = float(f.get("pd", f.max))
				if float(f.get("sweep_r", 0.0)) > 0.0:
					var sk: float = clampf(el / maxf(0.01, float(f.sweep_t)), 0.0, 1.0)
					if sk < 1.0 or el < float(f.sweep_t) + 0.12:
						var sa: float = 1.0 - clampf((el - float(f.sweep_t)) / 0.12, 0.0, 1.0)
						var srr: float = float(f.sweep_r) * (1.0 - pow(1.0 - sk, 3.0))
						if Bal.v("beacon/sweep_px", 1.0) > 0.0:
							_sweep_px(wv, f.from, srr, sa)
						else:   # 0 = 11-08 前：HDR 淡紫 5 像素平滑线（网页没有 HDR，截成白色粗圈）
							g.wcv.draw_set_transform(f.from, 0.0, Vector2(1.0, wv.ground_y()))   # 与清除圈同一个地面椭圆
							g.wcv.draw_arc(Vector2.ZERO, srr, 0.0, TAU, 64, Color(1.7, 1.25, 2.1, 0.75 * sa), 5.0)
							g.wcv.draw_arc(Vector2.ZERO, srr * 0.94, 0.0, TAU, 64, Color(2.0, 1.9, 1.6, 0.5 * sa), 2.0)
							g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				if g.vfx.p2 and f.get("tex", false):
					# 溟痕退散帧条 fx_mire_dissolve（64×64 × 6 原生 1x，world_spec_1024）：按 PX 1:1，不按半径拉伸；
					# 一块 64 美术像素 = 128 世界单位，大溟痕在圆内按 96 世界单位间距多点铺（块与块叠一圈、格心离圆心 ≤ 半径）；_emit 层进光学发光层
					var dtx: Texture2D = g.tex.get("fx_mire_dissolve")
					var dhs: float = A.hires_of(dtx) if dtx != null else 1.0
					var detx: Texture2D = wv._mire_dissolve_emit() if g.optical_on else null
					var step: float = 64.0 * Game.PX
					var pitch: float = 48.0 * Game.PX
					var me: float = Bal.v("render/optical_mire_emit", 0.35)   # 每格都用，循环外读一次（docs/50 §26）
					for c in f.pts:
						var lp: float = (el - (float(c[2]) if c.size() > 2 else 0.0)) / maxf(0.01, pd)
						if lp <= 0.0 or lp >= 1.0:
							continue
						var mfr: int = clampi(int(lp * 6.0), 0, 5)
						var dcol := Color(1.0, 1.0, 1.0, minf(1.0, (1.0 - lp) * 2.0))
						var nn: int = maxi(0, ceili((float(c[1]) - step * 0.5) / pitch))
						for iy in range(-nn, nn + 1):
							for ix in range(-nn, nn + 1):
								var off := Vector2(ix, iy) * pitch
								if off.length() > float(c[1]) and (ix != 0 or iy != 0):
									continue
								var dp: Vector2 = ((c[0] + off) / Game.PX).round() * Game.PX
								g.vfx.spr_rot("fx_mire_dissolve", mfr, dp, 0.0, Game.PX / dhs, dcol)
								if detx != null:
									g.glow_tex_next.append([detx, Rect2(dp - Vector2(step, step) * 0.5, Vector2(step, step)), Rect2(mfr * 64, 0, 64, 64), Color(1, 1, 1, dcol.a * me)])
				elif g.vfx.p2:
					var gy: float = wv.ground_y()
					for c in f.pts:
						var lp2: float = (el - (float(c[2]) if c.size() > 2 else 0.0)) / maxf(0.01, pd)
						if lp2 <= 0.0 or lp2 >= 1.0:
							continue
						var k := lp2
						a = 1.0 - lp2
						var rr: float = float(c[1]) * (1.0 - pow(k, 0.7))
						if rr < 2.0:
							continue
						wv.tb_circle(c[0], rr * 0.85, Color(0.1, 0.03, 0.14, 0.45 * a), gy, 12)
						wv.tb_ring(c[0], rr, 2.5, Color(1.0, 0.6, 1.6, 0.8 * a), 20)
						wv.tb_ring(c[0], rr * 0.55, 1.5, Color(1.6, 1.2, 2.0, 0.5 * a), 14)
			"shard":
				var sv: Vector2 = Vector2.from_angle(f.rot + g.t * 8.0) * 5.0
				g.wcv.draw_colored_polygon(PackedVector2Array([f.pos - sv, f.pos + sv.orthogonal() * 0.5, f.pos + sv]), Color(1.2, 1.9, 2.4, a))
			"blood":
				# 流血：地面血迹
				for q in 5:
					var off := Vector2(sin(f.seed + q * 1.7), cos(f.seed * 1.3 + q)) * 7.0
					g.wcv.draw_set_transform(f.pos + off, 0.0, Vector2(1.0, 0.5))
					g.wcv.draw_circle(Vector2.ZERO, 3.0 + (q % 3), Color(0.5, 0.02, 0.05, 0.6 * a))
					g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"explode":
				# 爆炸：火光 + 冲击环
				var k := 1.0 - a
				var c: Color = f.col
				g.wcv.draw_circle(f.pos, f.r * (0.3 + 0.7 * k), Color(c.r * 2.2, c.g * 1.8, c.b * 1.2, 0.45 * a))
				g.wcv.draw_circle(f.pos, f.r * 0.45 * a, Color(2.8, 2.4, 1.6, a))
				if not f.get("op_hit", false):   # 干员法术弹（艾雅法拉熔岩弹）的冲击环不画（10-13 用户删），火光照画
					g.wcv.draw_arc(f.pos, f.r * (0.5 + 0.7 * k), 0.0, TAU, 32, Color(c.r * 2.4, c.g * 2.0, c.b * 1.4, a), 4.0)
			"cross":
				# 治疗：上升的绿色十字
				var age: float = f.max - f.life
				if age >= f.get("delay", 0.0):
					var p: Vector2 = f.pos + Vector2(0, -40.0 * (age - f.delay))
					if g.tex.get("fx_heal_cross") != null:
						g.vfx.spr_rot("fx_heal_cross", mini(3, int((age - f.delay) * 10.0)), p, 0.0, Game.PX * f.sz / 4.5, Color(1, 1, 1, a))
					else:
						var sz: float = f.sz
						var ca := Color(0.7, 2.2, 1.0, a)
						g.wcv.draw_rect(Rect2(p - Vector2(sz * 0.35, sz), Vector2(sz * 0.7, sz * 2.0)), ca)
						g.wcv.draw_rect(Rect2(p - Vector2(sz, sz * 0.35), Vector2(sz * 2.0, sz * 0.7)), ca)
			"drain":
				# 部件吸取（周围小怪被击杀削部件血）：一串金色光点从击杀点沿弧线飞进部件，末端部件闪一下
				var k := 1.0 - a
				var mid: Vector2 = (f.a + f.b) / 2.0 + Vector2(0, -30)
				for q in 5:
					var u: float = clampf(k * 1.5 - q * 0.1, 0.0, 1.0)
					if u <= 0.0 or u >= 1.0:
						continue
					var p: Vector2 = f.a.lerp(mid, u).lerp(mid.lerp(f.b, u), u)
					g.wcv.draw_circle(p, 3.5 - q * 0.4, Color(1.9, 1.6, 0.7, 0.9))
				if k > 0.65:
					g.wcv.draw_circle(f.b, 12.0 * (k - 0.65) / 0.35 + 4.0, Color(1.9, 1.6, 0.7, 0.5 * (1.0 - k) / 0.35))
			"beacon_burst":
				var k := 1.0 - a
				var rr: float = f.r * (1.0 - pow(1.0 - k, 3.0))
				g.wcv.draw_set_transform(f.pos, 0.0, Vector2(1.0, wv.ground_y()))
				g.wcv.draw_circle(Vector2.ZERO, rr, Color(1.6, 1.3, 0.7, 0.18 * a))
				g.wcv.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 64, Color(1.9, 1.6, 0.9, 0.9 * a), 6.0)
				g.wcv.draw_arc(Vector2.ZERO, rr * 0.8, 0.0, TAU, 64, Color(2.0, 2.0, 1.8, 0.6 * a), 2.0)
				g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				for q in 12:
					var dv := Vector2.from_angle(q * TAU / 12.0)
					g.wcv.draw_line(f.pos + dv * rr * 0.3, f.pos + dv * rr * 0.6, Color(1.9, 1.6, 0.9, 0.7 * a), 3.0)
			"spear_fly":
				var k := 1.0 - a
				var p: Vector2 = f.pos.lerp(f.to, k) + Vector2(0, -110.0 * sin(k * PI))
				var ang: float = k * TAU * 1.5
				if g.tex.get("proj_knight_spear") != null:
					# Codex v14 脱手长枪（40×8 × 2 帧，水平枪尖朝右）：旋转由程序做，落地冰环照旧程序画
					# 贴图是深色钢枪，世界被灯光压暗后几乎看不见：按敌方特效惯例用 >1 的冰蓝调色提亮（同原来程序线段的颜色）
					g.vfx.spr_rot("proj_knight_spear", int(g.t * 12.0) % 2, p, ang, Game.PX, Color(1.7, 1.9, 2.3))
				else:
					var dv := Vector2.from_angle(ang) * 34.0
					g.wcv.draw_line(p - dv, p + dv, Color(0.1, 0.12, 0.2, 0.9), 6.0)
					g.wcv.draw_line(p - dv, p + dv, Color(1.4, 1.6, 1.9), 3.0)
					g.wcv.draw_circle(p + dv, 4.0, Color(1.6, 1.9, 2.2))
				if k > 0.9:
					var gk: float = (k - 0.9) / 0.1
					g.wcv.draw_arc(f.to, 10.0 + 30.0 * gk, 0.0, TAU, 20, Color(0.8, 1.2, 1.7, 1.0 - gk), 2.0)
			"tide_trail":
				var k := 1.0 - a
				g.wcv.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.45))
				g.wcv.draw_circle(Vector2.ZERO, f.r * (0.7 + 0.5 * k), Color(0.3, 0.9, 1.0, 0.28 * a))
				g.wcv.draw_arc(Vector2.ZERO, f.r * (0.8 + 0.6 * k), 0.0, TAU, 24, Color(0.9, 1.6, 1.8, 0.6 * a), 2.0)
				g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				for q in 4:
					var ang: float = f.seed + q * 1.7
					g.wcv.draw_circle(f.pos + Vector2(cos(ang) * f.r * (0.6 + k), sin(ang) * f.r * 0.3 - 6.0 * k), 2.5 * a, Color(1.8, 2.0, 2.0, 0.8 * a))
			"glint":
				# 竖直闪光（换剑）：十字星从中间展开再收
				var k := 1.0 - a
				var L: float = 60.0 * sin(k * PI)
				g.wcv.draw_line(f.pos + Vector2(0, -L), f.pos + Vector2(0, L), Color(2.0, 2.0, 2.0, a), 3.0)
				g.wcv.draw_line(f.pos + Vector2(-L * 0.4, 0), f.pos + Vector2(L * 0.4, 0), Color(2.0, 2.0, 2.0, a), 2.0)
				g.wcv.draw_circle(f.pos, 6.0 * a, Color(2.0, 2.0, 2.0, a))
			"lob_shell":
				# 轰击炮弹（圣徒伊比利亚，docs/95 §6.2 C）：纯画面，从本体沿抛物线飞向落点圈心，地面画随高度缩放的阴影；Codex proj_saint_shell 缺图走程序圆弹
				var u: float = 1.0 - a
				var gp: Vector2 = f.a.lerp(f.b, u)
				var hgt: float = sin(u * PI) * clampf(f.a.distance_to(f.b) * 0.4, 60.0, 150.0)   # 弧高按射程：近处低抛，别钻到顶部 HUD 下面
				g.wcv.draw_circle(gp, 4.0 + 5.0 * u, Color(0.0, 0.0, 0.0, 0.25 + 0.3 * u))
				var sp: Vector2 = gp + Vector2(0, -hgt)
				var vang: float = (f.b - f.a).angle() - cos(u * PI) * 1.1 * signf((f.b - f.a).x + 0.001)
				if g.tex.get("proj_saint_shell") != null:
					g.vfx.spr_rot("proj_saint_shell", int(g.t * 8.0) % 2, sp, vang, Game.PX)
				else:
					g.wcv.draw_circle(sp, 10.0, Color(0.06, 0.04, 0.03))
					g.wcv.draw_circle(sp, 7.5, Color(1.7, 0.95, 0.45))
			"reflow":
				# 碎片回流（塑路者核心超时）：一串碎石沿弧线从碎片位置冲回本体，尾迹变红，末端在本体上炸一圈
				var k := 1.0 - a
				var mid: Vector2 = (f.a + f.b) / 2.0 + (f.b - f.a).orthogonal().normalized() * 40.0
				for q in 6:
					var u: float = clampf(k * 1.4 - q * 0.07, 0.0, 1.0)
					if u <= 0.0 or u >= 1.0:
						continue
					var p0: Vector2 = f.a.lerp(mid, u).lerp(mid.lerp(f.b, u), u)
					var u2: float = maxf(0.0, u - 0.14)
					var p1: Vector2 = f.a.lerp(mid, u2).lerp(mid.lerp(f.b, u2), u2)
					g.wcv.draw_line(p1, p0, Color(1.6, 0.45, 0.35, 0.8), 6.0)
					UI.diamond(g.wcv, p0, 8.0 - q * 0.7, Color(0.75, 0.8, 1.2, 1.0), Color(0.1, 0.1, 0.2, 0.9))
				if k > 0.7:
					var rk: float = (k - 0.7) / 0.3
					g.wcv.draw_arc(f.b, 20.0 + 40.0 * rk, 0.0, TAU, 32, Color(1.6, 0.45, 0.35, 1.0 - rk), 3.0)
			"tide_link":
				# 双层弯曲潮线与逆流光点：接潮生命连接、伊莎玛拉泪滴共鸣共用。
				var c: Color = f.col
				var normal: Vector2 = (f.b - f.a).orthogonal().normalized()
				for side in [-1.0, 1.0]:
					var points := PackedVector2Array()
					for q in 13:
						var u: float = float(q) / 12.0
						points.append(f.a.lerp(f.b, u) + normal * side * sin(u * PI * 2.0 + g.t * 11.0) * 7.0 * sin(u * PI))
					g.wcv.draw_polyline(points, Color(0.02, 0.08, 0.16, 0.65 * a), 9.0)
					g.wcv.draw_polyline(points, Color(c.r * 1.4, c.g * 1.6, c.b * 1.8, 0.8 * a), 3.0)
				for q in 5:
					var u: float = fposmod(float(q) / 5.0 + g.t * 0.9, 1.0)
					var bead: Vector2 = f.a.lerp(f.b, u)
					g.wcv.draw_circle(bead, 3.5, Color(1.6, 2.4, 2.5, 0.8 * a))
				g.wcv.draw_arc(f.a, 14.0, 0.0, TAU, 20, Color(c.r, c.g, c.b, a), 2.0)
				g.wcv.draw_arc(f.b, 14.0, 0.0, TAU, 20, Color(c.r, c.g, c.b, a), 2.0)
			"rift":
				# 地面裂隙（触手 / 巨触出现前的预警）
				var k := 1.0 - a
				g.wcv.draw_set_transform(f.pos + Vector2(0, 8), 0.0, Vector2(1.0, 0.45))
				g.wcv.draw_circle(Vector2.ZERO, f.r * (0.5 + 0.5 * k), Color(0.12, 0.02, 0.18, 0.6))
				g.wcv.draw_arc(Vector2.ZERO, f.r, 0.0, TAU, 36, Color(1.6, 0.7, 2.4, 0.4 + 0.5 * k), 2.0)
				for q in 5:
					var dv := Vector2.from_angle(q * TAU / 5.0 + f.r)
					g.wcv.draw_line(dv * f.r * 0.15, dv * f.r * (0.4 + 0.5 * k), Color(1.8, 0.9, 2.6, 0.8), 2.0)
				g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"tendril":
				# 从水月脚下伸向目标的触须线
				var pts := PackedVector2Array()
				var nrm: Vector2 = (f.b - f.a).orthogonal().normalized()
				for q in 13:
					var u := q / 12.0
					pts.append(f.a.lerp(f.b, u) + nrm * sin(u * PI * 2.0 + f.seed + g.t * 10.0) * 10.0 * (1.0 - u))
				g.wcv.draw_polyline(pts, Color(0.5, 0.2, 0.8, 0.55 * a), 5.0)
				g.wcv.draw_polyline(pts, Color(1.6, 0.9, 2.4, 0.8 * a), 1.5)
			"giant_t":
				# 巨型触手破土
				var k := 1.0 - a
				var fr := clampi(int(k * 6.0), 0, 4)
				var tc: Color = g.ch.tentacle_col(1.15) if g.ch.has_method("tentacle_col") else Color(1.3, 1.1, 1.6)
				g.vfx.spr("tentacle", 5, fr, f.pos + Vector2(0, 16), Game.PX * 4.2, false, tc, Vector2(0.5, 1.0))
				g.vfx.spr("tentacle", 5, fr, f.pos + Vector2(-50, 20), Game.PX * 2.6, true, tc * Color(0.9, 0.9, 0.9, 1.0), Vector2(0.5, 1.0))
				g.vfx.spr("tentacle", 5, fr, f.pos + Vector2(48, 22), Game.PX * 2.4, false, tc * Color(0.9, 0.9, 0.9, 1.0), Vector2(0.5, 1.0))
			"sprite":
				var spec: Array = Game.V6_FRAMES[f.name]
				var el: float = f.max - f.life - float(f.get("delay", 0.0))   # delay：延后开播（vfx.fx_sprite）
				if el < 0.0:
					continue
				var fr := mini(int(el * float(f.get("fps", spec[1]))), spec[0] - 1)   # fps：加快过的死亡帧条（vfx.death_shatter）
				var scol: Color = f.get("col", Color.WHITE)
				scol.a *= fdim
				if wv.lead_lv > 0 and f.get("lead", false):
					scol = wv.lead_col(scol)   # 队长放的帧条特效：提亮 / 暖色（docs/139 §11）
				if g.optical != null and g.optical.grains != null and g.optical.grains.body_frame(f, fr, int(spec[0])):
					continue   # 形状颗粒化（fx_grains.GRAIN_BODY，docs/138 §13）：这一帧由颗粒拼出形状
				if f.has("grow") and LateRead.on("v5"):   # docs/247 V5：干员主形按精英化 / 节点放大后再取整，精一起加厚 1 格
					var gtx: Texture2D = g.tex.get(f.name)
					var gs: Array = LateRead.grow_scale(g, gtx, int(spec[0]), f.scale, float(f.grow), A.hires_of(gtx) if gtx != null else 1.0)
					g.vfx.spr_rot(f.name, fr, f.pos, f.ang, gs[0], scol, f.get("anchor", Vector2(-1, -1)), f.get("flip", false), int(f.get("thick", 0)) if gs[1] else 0)
				else:
					g.vfx.spr_rot(f.name, fr, f.pos, f.ang, g.vfx.int_scale(f.scale), scol, f.get("anchor", Vector2(-1, -1)), f.get("flip", false))
				if f.get("ring", 0.0) > 0.0 and fr == 0:
					g.wcv.draw_arc(f.pos, f.ring, 0.0, TAU, 40, Color(2.2, 2.0, 1.6, 0.6), 1.5)
			"impact":
				# 唤醒命中：十字闪光
				var k := 1.0 - a
				var L := 30.0 + 70.0 * k
				var c: Color = f.col
				var gc := Color(c.r * 2.2, c.g * 2.2, c.b * 2.2, a)
				for q in 4:
					var dv := Vector2.from_angle(f.ang + q * PI / 2.0 + PI / 4.0)
					g.wcv.draw_line(f.pos - dv * L * (0.6 if q % 2 else 1.0), f.pos + dv * L * (0.6 if q % 2 else 1.0), gc, 5.0 * a + 1.0)
				g.wcv.draw_circle(f.pos, 18.0 * a + 4.0, Color(3.0, 2.6, 1.8, a * 0.8))
			"burst":
				# 创伤扩散：水花冲击
				var k := 1.0 - a
				var rr: float = f.r * (0.4 + 0.7 * k)
				var c: Color = f.col
				g.wcv.draw_circle(f.pos, rr, Color(c.r * 1.8, c.g * 1.6, c.b * 1.2, 0.25 * a))
				g.wcv.draw_arc(f.pos, rr, 0.0, TAU, 32, Color(c.r * 2.2, c.g * 2.0, c.b * 1.6, a), 5.0)
				g.wcv.draw_arc(f.pos, rr * 0.7, 0.0, TAU, 32, Color(0.6, 1.6, 2.0, a * 0.6), 2.0)
				if not f.get("op_spoke", false):   # 干员水花的放射纹不画（10-13 用户删），水花本体照画
					for q in 10:
						var dv := Vector2.from_angle(q * TAU / 10.0 + f.r)
						g.wcv.draw_line(f.pos + dv * rr * 0.8, f.pos + dv * (rr + 14.0 * a), Color(2.0, 1.8, 1.2, a), 2.0)
			"wpillar":
				# 潮汐柱：升起的水柱 + 水花
				var k := 1.0 - a
				var c: Color = f.col
				var hgt: float = f.r * 2.4 * minf(1.0, k * 3.0)
				var wd: float = f.r * 0.8 * a
				g.wcv.draw_rect(Rect2(f.pos + Vector2(-wd / 2.0, -hgt), Vector2(wd, hgt)), Color(c.r * 1.4, c.g * 1.4, c.b * 1.6, 0.35 * a))
				g.wcv.draw_rect(Rect2(f.pos + Vector2(-wd / 5.0, -hgt), Vector2(wd / 2.5, hgt)), Color(2.2, 2.6, 2.8, 0.6 * a))
				g.wcv.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.5))
				g.wcv.draw_arc(Vector2.ZERO, f.r * (0.6 + 0.6 * k), 0.0, TAU, 32, Color(c.r * 1.6, c.g * 1.6, c.b * 1.8, a), 3.0)
				g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"gcrack":
				# 共用地裂（render/ground_crack.gd，和干员的 crack 同款）：第一次画时按落点生成并缓存；写进 tb 批，循环后统一提交
				if not f.has("cd"):
					f["cd"] = GroundCrack.build(f.pos, f.r, f.get("ang"), f.get("opts", {}))
				GroundCrack.draw(f.cd, f.max - f.life, a, f.col, wv._gc_sink, float(f.get("grow_t", 0.06)), float(f.get("hot", 1.0)))
			"quake":
				# 震地 / 跳砸：地面裂纹放射
				var k := 1.0 - a
				var c: Color = f.col
				for q in 9:
					var dv := Vector2.from_angle(q * TAU / 9.0 + f.pos.x * 0.01)
					var l: float = f.r * (0.4 + 0.6 * minf(1.0, k * 2.5))
					g.wcv.draw_line(f.pos + dv * 8.0, f.pos + dv * l, Color(0.05, 0.03, 0.02, 0.8 * a), 3.0)
					g.wcv.draw_line(f.pos + dv * 8.0, f.pos + dv * l * 0.7, Color(c.r * 1.6, c.g * 1.4, c.b, a), 1.5)
				g.wcv.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.5))
				g.wcv.draw_arc(Vector2.ZERO, f.r * (0.3 + 0.7 * k), 0.0, TAU, 32, Color(c.r * 1.8, c.g * 1.6, c.b * 1.2, a * 0.8), 4.0)
				g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"bslash":
				# 横扫：宽弧刀光
				var c: Color = f.col
				var k := 1.0 - a
				var a0: float = f.ang - f.half + f.half * 2.0 * minf(1.0, k * 1.6)
				var a1: float = f.ang - f.half
				g.wcv.draw_arc(f.pos, f.r * 0.9, a1, a0, 24, Color(c.r * 1.8, c.g * 1.8, c.b * 1.8, a), 14.0)
				g.wcv.draw_arc(f.pos, f.r * 0.75, a1, a0, 24, Color(2.4, 2.6, 2.6, a), 4.0)
				g.wcv.draw_arc(f.pos, f.r * 0.5, a1, a0, 24, Color(c.r * 1.2, c.g * 1.2, c.b * 1.2, 0.5 * a), 8.0)
			"pillar":
				# 触手破土：光柱
				var c: Color = f.col
				var hgt := 90.0 * (1.0 - a * 0.3)
				g.wcv.draw_rect(Rect2(f.pos + Vector2(-7 * a, -hgt), Vector2(14 * a, hgt)), Color(c.r * 2.0, c.g * 2.0, c.b * 2.0, 0.35 * a))
				g.wcv.draw_rect(Rect2(f.pos + Vector2(-2, -hgt), Vector2(4, hgt)), Color(2.5, 2.5, 2.5, 0.6 * a))
			"ghost":
				# 倒影：半透明的水月残像
				wv.draw_player_at(f.pos, f.flip, Color(1.2, 0.8, 2.0, 0.55 * a), g.sprite.frame)
			"chain":
				# 束缚传播：锁链
				var n := 8
				for q in n:
					var p0: Vector2 = f.a.lerp(f.b, float(q) / n)
					UI.diamond(g.wcv, p0 + Vector2(0, -8), 4.0, Color(0.02, 0.05, 0.08, a), Color(0.7, 1.4, 2.0, a))
			"boss_phase":
				# Boss 换幕：两圈洋红冲击波 + 12 道放射光刺
				var k := 1.0 - a
				var mc := Color(1.6, 0.45, 1.3)
				for q in 2:
					var kq: float = clampf(k * 1.3 - q * 0.25, 0.0, 1.0)
					if kq > 0.0 and kq < 1.0:
						var rq: float = f.r * (1.2 + 6.0 * (1.0 - pow(1.0 - kq, 2.0)))
						g.wcv.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.55))
						g.wcv.draw_arc(Vector2.ZERO, rq, 0.0, TAU, 64, Color(mc.r, mc.g, mc.b, (1.0 - kq) * 0.9), 6.0 - q * 2.0)
						g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				for q in 12:
					var dv := Vector2.from_angle(q * TAU / 12.0 + 0.26)
					var r0: float = f.r * (0.8 + 3.0 * k)
					g.wcv.draw_line(f.pos + dv * r0, f.pos + dv * (r0 + f.r * 1.6 * a + 10.0), Color(mc.r, mc.g, mc.b, a), 3.0)
			"boss_down":
				# Boss 倒下：核心爆闪 → 三道冲击环 → 光柱收细
				var k := 1.0 - a
				var el: float = f.max - f.life
				var dbc: Color = f.get("bcol", Color(1.0, 0.95, 1.0))   # 专属色系（亮 → 本色 → 暗），核心不再白闪
				if el < 0.3:
					var ck: float = el / 0.3
					g.wcv.draw_circle(f.pos, f.r * (1.0 + 1.5 * ck), Color(dbc.r * 1.4, dbc.g * 1.4, dbc.b * 1.4, (1.0 - ck) * 0.55))
				var cols := [Color(dbc.r * 0.5 + 0.7, dbc.g * 0.5 + 0.7, dbc.b * 0.5 + 0.7), Color(dbc.r * 1.2, dbc.g * 1.2, dbc.b * 1.2), Color(dbc.r * 0.6, dbc.g * 0.6, dbc.b * 0.6)]
				for q in 3:
					var kq: float = clampf((el - q * 0.14) / 1.1, 0.0, 1.0)
					if kq > 0.0 and kq < 1.0:
						var rq: float = f.r * (1.0 + 7.0 * (1.0 - pow(1.0 - kq, 3.0)))
						var cq: Color = cols[q]
						g.wcv.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.55))
						g.wcv.draw_arc(Vector2.ZERO, rq, 0.0, TAU, 72, Color(cq.r, cq.g, cq.b, (1.0 - kq) * 0.85), 7.0 - q * 2.0)
						g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				var pw: float = f.r * 1.4 * (1.0 - k * k)
				if pw > 0.5:
					g.wcv.draw_rect(Rect2(f.pos.x - pw / 2.0, f.pos.y - 520.0, pw, 520.0 + f.r * 0.4), Color(1.8, 1.6, 2.0, 0.55 * a))
					g.wcv.draw_rect(Rect2(f.pos.x - pw / 6.0, f.pos.y - 520.0, pw / 3.0, 520.0 + f.r * 0.4), Color(2.0, 2.0, 2.0, 0.8 * a))
			"rays":
				# 技能发动：放射光束（op_spoke = 干员发的，10-13 用户删、不画；晋升 / 宝箱 / 祭坛 / 藏品 / 敌方照画）
				if f.get("op_spoke", false):
					continue
				var k := 1.0 - a
				var c: Color = f.col
				for q in 16:
					var dv := Vector2.from_angle(q * TAU / 16.0 + k * 0.6)
					var r0 := 30.0 + 200.0 * k
					g.wcv.draw_line(f.pos + dv * r0, f.pos + dv * (r0 + 60.0 * a + 20.0), Color(c.r * 2.2, c.g * 2.2, c.b * 2.2, a), 3.0)
			"slash":
				var nf: int = f.get("frames", 4)
				var fr := clampi(int((1.0 - a) * float(nf)), 0, nf - 1)
				var tn: String = f.get("tex", "slash")
				g.wcv.draw_set_transform(f.pos, f.ang, Vector2.ONE)
				var sc_col: Color = f.col if (tn == "slash" or tn.begins_with("fx_umbrella_slash")) else Color.WHITE
				var ssc: float = f.scale
				if f.has("grow") and LateRead.on("v5"):   # docs/247 V5：刀光按精英化 / 节点放大（取整、上限同帧条）
					var stx: Texture2D = g.tex.get(tn)
					ssc = LateRead.grow_scale(g, stx, nf, f.scale, float(f.grow), A.hires_of(stx) if stx != null else 1.0)[0]
				g.vfx.spr(tn, nf, fr, Vector2.ZERO, ssc, false, sc_col, f.get("anchor", Vector2(0.5, 0.5)))
				g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	wv.tb_flush()   # gcrack 等写进 tb 批的特效在这里一次提交


static func _bfx_grains(wv: W, f: Dictionary) -> void:
	var g: Game = wv.g
	var c: Color = f.bfx
	var gr = W._BfxCap.new(wv.bfx_grains, BossBeam.take(g, W.BFX_CAP.get(str(f.kind), 32)))
	var p: Vector2 = f.get("pos", Vector2.ZERO)
	match str(f.kind):
		"ring":
			var r: float = float(f.get("r", 40.0))
			var n: int = clampi(int(r * 0.35), 16, 48)
			for i in n:
				var d := Vector2.from_angle(TAU * i / n + g.vrng.randf_range(-0.08, 0.08))
				gr.push("bfx_burst", p + Vector2(d.x, d.y * 0.72) * r, d, c)
		"explode":
			var r2: float = float(f.get("r", 40.0))
			for i in 44:
				var d2 := Vector2.from_angle(g.vrng.randf() * TAU)
				gr.push("bfx_burst", p + d2 * r2 * g.vrng.randf_range(0.0, 0.35), d2, c)
			for i in 12:
				gr.push("bfx_dust", p + Vector2(g.vrng.randf_range(-0.5, 0.5) * r2, 0), Vector2.UP, c)
		"wpillar":
			# 水柱：一柱颗粒自下而上（不再是两个矩形）
			var r3: float = float(f.get("r", 40.0))
			for i in 34:
				var y: float = -g.vrng.randf() * r3 * 2.2
				gr.push("bfx_dust", p + Vector2(g.vrng.randf_range(-0.35, 0.35) * r3, y), Vector2.UP, c, g.vrng.randf() * 0.12)
			for i in 14:
				var d3 := Vector2.from_angle(PI + g.vrng.randf() * PI)
				gr.push("bfx_burst", p + Vector2(d3.x * r3 * 0.5, 0), d3, c)
		"quake":
			var r4: float = float(f.get("r", 60.0))
			var dc := Color(c.r * 0.55 + 0.25, c.g * 0.55 + 0.22, c.b * 0.55 + 0.2)   # 尘土：专属色掺土灰
			for i in 36:
				var d4 := Vector2.from_angle(g.vrng.randf() * TAU)
				gr.push("bfx_dust", p + Vector2(d4.x, d4.y * 0.6) * r4 * g.vrng.randf_range(0.2, 1.0), d4, dc)
		"bslash":
			# 刀光：沿弧撒刀光颗粒（切向 + 略向外），顺着挥刀方向依次出（emit_delay）
			var r5: float = float(f.get("r", 80.0))
			var a0: float = float(f.ang) - float(f.half)
			for i in 30:
				var u: float = float(i) / 29.0
				var aa: float = a0 + float(f.half) * 2.0 * u
				var d5 := Vector2.from_angle(aa)
				gr.push("slash", p + d5 * r5 * g.vrng.randf_range(0.55, 0.92), (d5.orthogonal() + d5 * 0.6).normalized(), c, u * 0.12)
		"rays":
			for i in 20:
				var d6 := Vector2.from_angle(TAU * i / 20.0)
				gr.push("bfx_burst", p + d6 * 20.0, d6, c)
		"tracer":
			var pa: Vector2 = f.a
			var pb: Vector2 = f.b
			var nrm: Vector2 = (pb - pa).orthogonal().normalized()
			for i in 22:
				var u2: float = g.vrng.randf()
				gr.push("bfx_flash", pa.lerp(pb, u2), nrm * (1.0 if g.vrng.randf() < 0.5 else -1.0), c, u2 * 0.04)   # 激光类收尾 ≤ 0.25 秒（用户 10-26）


static func _sweep_px(wv: W, c: Vector2, rr: float, sa: float) -> void:
	var g: Game = wv.g
	if rr < 4.0 or sa <= 0.0:
		return
	var px: float = Game.PX
	var gy: float = wv.ground_y()
	var n: int = clampi(int(TAU * rr / px), 24, 2400)
	var cf := Color(SWEEP_FRONT.r, SWEEP_FRONT.g, SWEEP_FRONT.b, 0.9 * sa)
	var cb := Color(SWEEP_BACK.r, SWEEP_BACK.g, SWEEP_BACK.b, 0.6 * sa)
	var glow: bool = g.optical_on
	var gc := Color(SWEEP_FRONT.r, SWEEP_FRONT.g, SWEEP_FRONT.b, 0.5 * sa)
	var seed: int = int(c.x * 0.37 + c.y * 1.91)
	var last := Vector2.INF
	var last_b := Vector2.INF
	var d := Vector2(px, px)
	for i in n:
		if (hash(Vector2i(i / 7, seed)) & 1023) < 205:   # 断口：约两成
			continue
		var a: float = i * TAU / n
		var u := Vector2(cos(a), sin(a) * gy)
		var p: Vector2 = ((c + u * rr) / px).floor() * px
		if p != last:
			last = p
			wv.tb_quad(p, p + Vector2(px, 0), p + d, p + Vector2(0, px), cf)
			if glow and i % 3 == 0:
				g.glow_next.append([p, px, gc])
		var q: Vector2 = ((c + u * (rr - px * 1.5)) / px).floor() * px
		if q != last_b and q != last:
			last_b = q
			wv.tb_quad(q, q + Vector2(px, 0), q + d, q + Vector2(0, px), cb)


## 刀光第四版：把这一帧前沿新扫过的角度段 [上帧前沿, 本帧前沿] 按月牙剖面（外沿到内沿，2 世界像素一格）取样成颗粒发射点，
## 初速沿挥刀切线（惯性），颜色 = 干员本色（模板颜色阶乘在上面：热白 → 本色 → 冷暗）；单帧点数超模板上限时均匀抽稀。
## 前沿另画一道 2 px 热白细线，读出「刀口」；尾部不画实体，由颗粒自己冷却熄灭
static func _marc_grains(wv: W, f: Dictionary, gr, ap: Vector2, rc: float, tw: float, s0: float, sw: float, hd: float, cc: Color, kb: float, aq: float) -> void:
	var g: Game = wv.g
	var u0: float = float(f.get("gu", 0.0))
	if hd > u0 + 0.001 and (gr.pos.size() >= gr.budget() or not gr.view.has_point(ap)):
		f["gu"] = hd   # 颗粒已满 / 挥刀点在屏外（docs/50 §26）：这段不取样（push 反正全丢），刀口线照画
	elif hd > u0 + 0.001:
		var cells: Array = []
		var nu: int = maxi(1, int(absf(sw) * (hd - u0) * rc / 2.0))
		for i in nu:
			var u: float = lerpf(u0, hd, (float(i) + 0.5) / float(nu))
			var uu: float = clampf(u, 0.0, 1.0)
			var th: float = tw * pow(sin(PI * uu), 0.6) * (0.35 + 0.65 * uu)
			var ang: float = s0 + sw * u
			var dv := Vector2.from_angle(ang)
			var tg := dv.orthogonal() * signf(sw)   # 挥刀切线方向
			var nr: int = maxi(1, int(th / 2.0))
			for j in nr:
				cells.append([ap + dv * (rc - float(j) * 2.0), tg])
		var cap: int = int(gr.TEMPLATES.slash.per_frame)
		var stride: float = maxf(1.0, float(cells.size()) / float(cap))
		var k: float = 0.0
		var col := Color(minf(1.0, cc.r * kb), minf(1.0, cc.g * kb), minf(1.0, cc.b * kb), cc.a)
		while int(k) < cells.size():
			var c: Array = cells[int(k)]
			gr.push("slash", c[0], c[1], col)
			k += stride
		f["gu"] = hd
	if hd < 1.0:
		var e0: float = s0 + sw * maxf(0.0, hd - 0.06)
		var e1: float = s0 + sw * hd
		g.wcv.draw_arc(ap, rc - 1.0, minf(e0, e1), maxf(e0, e1), 6, Color(2.0, 2.0, 2.0, aq), 2.0)   # 刀口热白线


## 近战刀光月牙（"marc"）：外沿在半径 r 的圆上，内沿离外沿 thick × sin(π u)；u 是整次挥刀上的位置（0 起点 / 1 终点），
## 只画 [u0, u1] 那一段（跟着挥刀扫）。起点角 s0，扫过 sweep（带方向的弧度）
static func _crescent(wv: W, c: Vector2, r: float, s0: float, sweep: float, u0: float, u1: float, thick: float, col: Color, _k: float) -> void:
	var g: Game = wv.g
	var n: int = clampi(int(absf(sweep) * (u1 - u0) * r / 4.0), 3, 40)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in n + 1:
		var u: float = lerpf(u0, u1, float(i) / float(n))
		var ang: float = s0 + sweep * u
		var uu: float = clampf(u, 0.0, 1.0)
		var th: float = thick * pow(sin(PI * uu), 0.6) * (0.35 + 0.65 * uu)   # 前粗后尖（彗星形）：靠挥刀终点一侧最厚
		var dv := Vector2.from_angle(ang)
		outer.append(c + dv * r)
		inner.append(c + dv * maxf(0.0, r - th))
	inner.reverse()
	outer.append_array(inner)
	if outer.size() >= 3:
		g.wcv.draw_colored_polygon(outer, col)
