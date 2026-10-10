extends RefCounted
## Boss 登场演出（用户 10-10）：10 只 Boss 共用一套约 1.5 秒的纯覆盖层演出，数据按 Boss 填（CARDS）：
##   上下黑边滑入（docs/37 青 / Boss 强调色细线）→ 暗角 → 名片（中文大字 + 压缩斜体英文副标 + 小标签「BOSS · 标题」+ 一句台词 + 待机条头像）
##   世界层：Boss 脚下聚光圈 + 两圈扩散环（tb_* 合批）；本体先是白剪影、0.15–0.7 秒亮成本体（world._draw_enemy_full 读 silhouette_k）。
## 规则：模拟照常跑——不暂停、不改刷怪时机、不碰 g.rng（只有画面，随机只用 g.vrng）；同 seed 对局逐字段不变（docs/36 §3）。
##   无头批跑 / 图鉴演示 / --nobossintro / 设置「Boss 登场演出」关：整段不跑。低画质：不画暗角、扩散环和头像。
##   不震屏（docs/38 §1.8 / §6.3）。音乐：仍由 spawner 的 boss_in 叠句 + music_director 换 Boss 曲负责，这里只补这只 Boss 的专属音色一记（docs/38 §8.11 的 boss_<id>）。
## 击破（同一套）：world.watch_bosses 观察到真 Boss 倒下 → 0.6 秒缓慢褪去的白闪 + 名字一行「击破」。
## 测试：--bossintro=<id>[,<id>]（autotest.gd）在主控旁刷出该 Boss 并走一遍登场 / 击破，定时截图；docs/36 §5。

const Game = preload("res://scripts/game.gd")
const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
var g: Game

const DUR := 1.5          # 登场演出总长（秒，真实时间；面板 / 暂停时停表）
const OUT_DUR := 0.6      # 击破一拍
const BAR_T := 0.25       # 黑边滑入 / 滑出用时

## 名片数据（每只 Boss 一条；缺的字段按缺省）：
##   cn 名字行（缺省 enemies.json 的 name）、en 英文副标、sub 一句标题（小标签右段）、col 强调色（缺省 vfx.BOSS_STYLE 的招式色）、
##   sfx 登场音（缺省 boss_<id>，Sfx.CUE_VOL 里有电平；没有文件就静默）、portrait 头像帧条（缺省 e.tex 待机条第 0 帧）、line 一句台词（lore.json 口径）
const CARDS := {
	"path": {"en": "PATHSHAPER", "sub": "替大群探路的海嗣", "line": "它把自己的碎片撒向每一条岔路，让它们先去走那些错的路。"},
	"iberia": {"en": "SAINT OF IBERIA", "sub": "老猎人的枪 · 强化", "line": "斗篷破了，他不再说话；手炮只装一发，装得更快、打得更狠。"},
	"carmen": {"en": "SAINT CARMEN", "sub": "伊比利亚最后的圣徒", "line": "退后、装填、瞄准——弹药打空就用炮身砸过来，他仍记得谁是敌人。"},
	"bishop": {"en": "TIDE BISHOP", "sub": "分离与统一", "line": "一方倒下只是假死，两者同时倒下才会真正消散。"},
	"archon": {"en": "TIDE DEFIER", "sub": "与主教同生共死", "line": "粗壮的近战海嗣——单独击倒它只会让它假死片刻。"},
	"immortal": {"en": "TIDE REBUKER", "sub": "与主教共享同一份执念", "line": "迅捷的近战海嗣，与主教同生共死。"},
	"paranoia": {"cn": "「偏执泡影」", "en": "PARANOIA", "sub": "最终 · 变成最厌恶的样子", "line": "大群的祈望堵住了她的喉咙，她只能被那股力量拖着，一点点变成自己最痛恨的模样。"},
	"ishar": {"en": "ISHAR-MLA, CORRUPTED HEART", "sub": "最终 · 替大群发声", "line": "转化完成后，深海的敌意才显露出来。"},
	"izumik": {"en": "IZUMIK, FOUNT OF LIFE", "sub": "最终 · 人之光辉", "line": "海嗣的母体之一，生命从它身上涌出，也在它身上腐烂。"},
	"knight_boss": {"en": "THE LAST KNIGHT", "sub": "最终 · 堂吉诃德", "line": "曾经护送旅人穿越海嗣领地的猎潮骑士，如今成为海潮的一部分。"},
}

## 最终 Boss 击破演出（docs/38 §1.8，10-11）：run/victory_flow.gd 把画面步长压到慢动作（真实 2 秒），这里只画覆盖层：
##   白闪褪去 → 黑边滑入（内缘结局色细线）→ 结局色洗色 + 暗角 + 后期去色（低画质不洗色、不去色）→ 「名字 · 击破 / DEFEATED」名片 → 末 0.3 秒收黑边
##   配乐：music_director 在演出开始就放结算乐句。同样不震屏、不碰模拟；无头 / 设置关 / 演练不演，平衡批跑只在 --bossdeath 下演（录片用）。
const FIN_DUR := 2.0       # 和 victory_flow.FIN_DUR 一致（真实秒）
const FIN_DESAT := 0.55    # 去色强度峰值（post.gdshader desat）

var cur := {}      # 进行中的登场：{bosses: [敌人字典…], card: Dictionary, t: 秒}
var outro := {}    # 进行中的击破一拍：{name, col, t}
var finale := {}   # 进行中的最终 Boss 击破演出：{name, en, col 结局色, bcol Boss 强调色, t 真实秒}
var _test_shots: Array = []   # --bossintro 的截图时刻（autotest 用）
var _top: Control = null      # 自己的顶层画布：HUD 的合批 / 缓存层都是 g.hud 的子节点（画在父节点之上），黑边要盖住它们就得是最后一个子节点


func _init(game: Game) -> void:
	g = game


## 整段演出要不要跑：无头批跑 / 图鉴演示 / --nobossintro / 设置关 都不跑；平衡批跑开着窗口（宣传录制）照常演
func enabled() -> bool:
	if DisplayServer.get_name() == "headless" or g.headless_batch or g.demo_op != "":
		return false
	if not Cfg.boss_intro or Cfg.dev_args().has("--nobossintro"):
		return false
	return true


func active() -> bool:
	return not cur.is_empty()


## 最终 Boss 击破演出要不要跑：登场演出的同一开关，再加只在正式游玩（或 --bossdeath 测试 / 录片）下演；平衡批跑 / 自测照旧立即结算
func finale_ok() -> bool:
	if not enabled():
		return false
	if g.mode == Game.Mode.PLAY:
		return true
	for a in Cfg.dev_args():
		if str(a).begins_with("--bossdeath="):
			return true
	return false


## 最终 Boss 倒下（victory_flow.begin）：开始击破演出；替代普通的击破一拍
func on_finale(b: Dictionary) -> void:
	var c := card_for([b])
	finale = {"name": str(c.cn), "en": str(c.en), "col": g.endg.cur_col(), "bcol": c.col, "t": 0.0}
	outro = {}
	cur = {}


## 一组 Boss（同时登场的接潮双体算一组）刚被 spawner 刷出来：登场演出 + 专属音色。只有 role == boss 的算
## 友方阶段的 Boss（伊莎玛拉人形）不在刷出时演，等 world.watch_bosses 看到它转为敌对再演（force：测试开关直接演）
func on_spawn(group: Array, force := false) -> void:
	if not enabled():
		return
	var bosses: Array = group.filter(func(b): return b != null and D.ENEMIES.get(b.type, {}).get("role", "") == "boss" and (force or not b.get("friendly", false)))
	if bosses.is_empty():
		return
	cur = {"bosses": bosses, "card": card_for(bosses), "t": 0.0}
	var sfx: String = str(cur.card.sfx)
	if sfx != "":
		Sfx.play(sfx, float(Sfx.CUE_VOL.get(sfx, -22.0)) + 6.0, 1.0, 0.0)


## 真 Boss 倒下（world.watch_bosses 观察到；撤退 / 友方不算）：击破一拍
func on_down(b: Dictionary) -> void:
	if not enabled() or b.get("friendly", false) or b.get("retreated", false):
		return
	if D.ENEMIES.get(b.type, {}).get("role", "") != "boss" or not finale.is_empty():
		return   # 最终 Boss 走 on_finale 的整段演出，不再叠普通一拍
	var c := card_for([b])
	outro = {"name": str(c.cn), "col": c.col, "t": 0.0}
	cur = {}   # 登场还没播完就被秒了：直接切到击破


## 按 Boss 组拼名片：第一只为主，双体把名字用「与」连起来、英文用 & 连
func card_for(bosses: Array) -> Dictionary:
	var main: Dictionary = bosses[0]
	var cd: Dictionary = CARDS.get(main.type, {})
	var def: Dictionary = D.ENEMIES.get(main.type, {})
	var cn: String = str(cd.get("cn", def.get("name", main.type)))
	var en: String = str(cd.get("en", main.type.to_upper()))
	for i in range(1, bosses.size()):
		var b2: Dictionary = bosses[i]
		var cd2: Dictionary = CARDS.get(b2.type, {})
		cn += " 与 " + str(cd2.get("cn", D.ENEMIES.get(b2.type, {}).get("name", b2.type)))
		en += " & " + str(cd2.get("en", b2.type.to_upper()))
	var col: Color = cd.get("col", g.vfx.boss_color(main.type))
	return {"cn": cn, "en": en, "sub": str(cd.get("sub", "")), "col": col, "line": str(cd.get("line", "")),
		"sfx": str(cd.get("sfx", "boss_" + main.type)), "portrait": str(cd.get("portrait", main.tex)), "type": main.type}


## 每渲染帧（game._process 的 delta，真实时间）：面板 / 非战斗状态时停表，关掉后接着播
func update(delta: float) -> void:
	if g.state != Game.S.PLAY:
		finale = {}   # 结算面板 / 暂停接管：击破演出到此为止（后期去色也随之归零）
		_set_desat(0.0)
		return
	if g.panel.visible:
		return
	if not cur.is_empty():
		cur.t += delta
		if cur.t >= DUR:
			cur = {}
	if not outro.is_empty():
		outro.t += delta
		if outro.t >= OUT_DUR:
			outro = {}
	if not finale.is_empty():
		finale.t += delta
		if finale.t >= FIN_DUR or not g.victory.active:
			finale = {}
		_set_desat(0.0 if finale.is_empty() or Cfg.quality == "low" else FIN_DESAT * _fin_env(float(finale.t)))
	if _top != null and _top.visible:
		_top.queue_redraw()


## 洗色 / 去色的包络：0.1–0.5 秒进、末 0.5 秒退
static func _fin_env(t: float) -> float:
	return _ss(0.1, 0.5, t) * (1.0 - _ss(FIN_DUR - 0.5, FIN_DUR, t))


func _set_desat(k: float) -> void:
	if g.post != null and g.post.desat != k:
		g.post.desat = k


## 顶层画布：第一次用到时建在 g.hud 下、移到最后（最上面）；没有演出时隐藏，不占绘制
func _canvas() -> Control:
	if _top == null:
		_top = Control.new()
		_top.set_anchors_preset(Control.PRESET_FULL_RECT)
		_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_top.name = "BossIntro"
		g.hud.add_child(_top)
		_top.draw.connect(_draw_top)
	if g.hud.get_child(g.hud.get_child_count() - 1) != _top:
		g.hud.move_child(_top, -1)
	return _top


## 本体白剪影的不透明度（world._draw_enemy_full：登场的 Boss 先是白剪影，0.15–0.7 秒亮成本体）
func silhouette_k(e: Dictionary) -> float:
	if cur.is_empty():
		return 0.0
	var t: float = cur.t
	if t >= 0.7:
		return 0.0
	for b in cur.bosses:
		if is_same(b, e):
			return 1.0 if t < 0.15 else 1.0 - (t - 0.15) / 0.55
	return 0.0


static func _ss(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)


## 世界层（world.draw_world，敌人之前、结晶之后）：脚下聚光圈 + 两圈扩散环，tb_* 合批，一次 flush
func draw_world() -> void:
	if cur.is_empty():
		return
	var t: float = cur.t
	var col: Color = cur.card.col
	var low: bool = Cfg.quality == "low"
	var fade: float = 1.0 - _ss(DUR - 0.35, DUR, t)
	for b in cur.bosses:
		if b.dead:
			continue
		var c: Vector2 = b.pos + Vector2(0, b.r * 0.8)
		var rr: float = maxf(b.r, 24.0)
		# 聚光：脚下亮椭圆（随呼吸微动）+ 一圈细环
		var k_in: float = _ss(0.0, 0.3, t)
		var breathe: float = 1.0 + 0.04 * sin(t * 9.0)
		g.world.tb_circle(c, rr * 2.4 * breathe, Color(col.r * 1.6, col.g * 1.6, col.b * 1.6, 0.22 * k_in * fade), 0.45, 20)
		g.world.tb_circle(c, rr * 1.3 * breathe, Color(2.0, 2.0, 2.0, 0.12 * k_in * fade), 0.45, 16)
		g.world.tb_arc(c, rr * 2.4 * breathe, 0.0, TAU, 2.0, Color(col.r * 2.0, col.g * 2.0, col.b * 2.0, 0.7 * k_in * fade), 28, 0.45)
		if low:
			continue
		# 两圈错开的扩散环（0.0 / 0.25 秒起，各 0.9 秒）
		for q in 2:
			var tq: float = (t - 0.25 * q) / 0.9
			if tq <= 0.0 or tq >= 1.0:
				continue
			var r2: float = rr * 1.5 + tq * 220.0
			g.world.tb_arc(c, r2, 0.0, TAU, 3.0 * (1.0 - tq) + 1.0, Color(col.r * 2.0, col.g * 2.0, col.b * 2.0, 0.55 * (1.0 - tq) * fade), 32, 0.45)
		# 八道放射细线（只在前 0.5 秒）
		if t < 0.5:
			var kr: float = 1.0 - t / 0.5
			for q in 8:
				var ang: float = q * TAU / 8.0 + 0.3
				var dv := Vector2(cos(ang), sin(ang) * 0.45)
				g.world.tb_line(c + dv * rr * 1.6, c + dv * (rr * 1.6 + 60.0 * (1.0 - kr)), Color(2.0, 2.0, 2.0, 0.35 * kr), 1.5)
	g.world.tb_flush()


## HUD 层（hud._draw_body 每帧调）：有演出时让顶层画布显示并重画，没有就藏起来
func draw_hud(_vs: Vector2) -> void:
	var on: bool = not cur.is_empty() or not outro.is_empty() or not finale.is_empty()
	if not on:
		if _top != null:
			_top.visible = false
		return
	var c := _canvas()
	if not c.visible:
		c.visible = true
		c.queue_redraw()


## 顶层画布的绘制：黑边、暗角、名片；击破一拍
func _draw_top() -> void:
	var vs: Vector2 = g.hud.size
	var ci: CanvasItem = _top
	if not finale.is_empty():
		_draw_finale(vs, ci)
		return
	if not outro.is_empty():
		_draw_outro(vs, ci)
	if cur.is_empty():
		return
	var t: float = cur.t
	var card: Dictionary = cur.card
	var col: Color = card.col
	var low: bool = Cfg.quality == "low"
	var touch: bool = g.touch.active
	# 黑边：0–0.25 滑入，末 0.25 滑出（触屏黑边薄一点，别盖住摇杆 / 技能键）
	var kb: float = _ss(0.0, BAR_T, t) * (1.0 - _ss(DUR - BAR_T, DUR, t))
	var bh: float = vs.y * (0.085 if touch else 0.12) * kb
	if bh > 0.5:
		ci.draw_rect(Rect2(0, 0, vs.x, bh), Color(0.01, 0.012, 0.02, 1.0))
		ci.draw_rect(Rect2(0, vs.y - bh, vs.x, bh), Color(0.01, 0.012, 0.02, 1.0))
		# 黑边内缘：从中间向两侧亮起的强调色细线（docs/37 渐隐细线）
		var lk: float = _ss(0.1, 0.5, t)
		for yy in [bh, vs.y - bh]:
			UI.hairline(ci, Vector2(vs.x / 2.0, yy), Vector2(vs.x / 2.0 - vs.x * 0.5 * lk, yy), col, 0.9 * kb, 0.0)
			UI.hairline(ci, Vector2(vs.x / 2.0, yy), Vector2(vs.x / 2.0 + vs.x * 0.5 * lk, yy), col, 0.9 * kb, 0.0)
	# 暗角：0.1–0.4 进、末 0.3 退（低画质不画）
	if not low:
		var kv: float = _ss(0.1, 0.4, t) * (1.0 - _ss(DUR - 0.3, DUR, t))
		if kv > 0.01:
			ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.01, 0.02, 0.30 * kv))
			_edge_glow(ci, vs, Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 0.55 * kv), 150.0)
	# 名片：0.2 起从左滑入，1.25 起淡出
	var a: float = _ss(0.2, 0.45, t) * (1.0 - _ss(DUR - 0.25, DUR - 0.05, t))
	if a <= 0.01:
		return
	var slide: float = (1.0 - _ss(0.2, 0.5, t)) * 36.0
	var cx: float = vs.x * 0.5
	var y0: float = maxf(vs.y * 0.36, g.hud_view.bars.boss_bottom + 60.0)   # 在横幅（vs.y*0.24）和 Boss 血条之下、主控之上
	var name_size: int = 34 if touch or vs.y < 680 else 40
	var font: Font = g.font
	var nw: float = font.get_string_size(card.cn, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x
	var pw: float = 0.0
	var ptx: Texture2D = null if low else g.tex.get(card.portrait)
	if ptx != null:
		pw = 92.0
	var total_w: float = nw + pw
	var x0: float = cx - total_w * 0.5 - slide
	# 半透明暗带托底（两端渐隐）
	var band := Rect2(cx - maxf(total_w, 420.0) * 0.5 - 60.0, y0 - 54.0, maxf(total_w, 420.0) + 120.0, 118.0)
	UI.fade_band(ci, band, Color(0.03, 0.035, 0.045, 0.72 * a), 120.0)
	# 头像：待机帧条第 0 帧放大到 80 高，左侧细边与强调色底
	if ptx != null:
		var fw: int = ptx.get_width() / 2
		var fh: int = ptx.get_height()
		var sc: float = minf(84.0 / float(fh), 84.0 / float(fw))
		sc = floorf(sc) if sc >= 1.0 else sc
		var sz := Vector2(fw, fh) * sc
		var pc := Vector2(x0 + 42.0, y0 - 2.0)
		ci.draw_rect(Rect2(pc - Vector2(44, 44), Vector2(88, 88)), Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.8 * a))
		ci.draw_rect(Rect2(pc - Vector2(44, 44), Vector2(88, 88)), Color(col.r, col.g, col.b, 0.9 * a), false, 1.0)
		ci.draw_texture_rect_region(ptx, Rect2((pc - sz * 0.5).round(), sz), Rect2(0, 0, fw, fh), Color(1, 1, 1, a))
		x0 += pw
	# 左侧强调色竖条 + 小标签「BOSS · 标题」
	ci.draw_rect(Rect2(x0 - 14.0, y0 - 40.0, 4.0, 78.0), Color(col.r, col.g, col.b, a))
	var sub_cn: String = card.sub if card.sub != "" else ("最终 Boss" if g.final_boss != null and cur.bosses.any(func(b): return is_same(b, g.final_boss)) else "中期 Boss")
	var scol := Color(col.r, col.g, col.b, a)
	UI.strip(ci, font, Vector2(x0 - 4.0, y0 - 42.0), "BOSS", sub_cn, scol, Color(1, 1, 1, a), 12, Color(0.0, 0.0, 0.0, 0.6))
	# 名字大字（白，带描边）+ 英文压缩副标（强调色，带字距）
	UI.text(ci, font, Vector2(x0 - 4.0, y0 + 20.0), card.cn, name_size, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 4)
	UI.en(ci, font, Vector2(x0 - 2.0, y0 + 42.0), card.en, 14, Color(col.r * 1.1, col.g * 1.1, col.b * 1.1, a), 3.0)
	# 一句台词（0.45 起，小字、次要色；触屏窄屏按宽度缩字）
	if card.line != "":
		var la: float = a * _ss(0.45, 0.7, t)
		var fl: Array = UI.fit_line(font, card.line, 14, vs.x * 0.72, 11)
		UI.text(ci, font, Vector2(0, y0 + 64.0), fl[0], fl[1], Color(0.8, 0.85, 0.88, la), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)


## 四边渐隐的边光（同 hud.edge_glow，画在自己的画布上）
static func _edge_glow(ci: CanvasItem, vs: Vector2, col: Color, w: float) -> void:
	var c0 := col
	var c1 := Color(col.r, col.g, col.b, 0.0)
	ci.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), Vector2(vs.x, w), Vector2(0, w)]), PackedColorArray([c0, c0, c1, c1]))
	ci.draw_polygon(PackedVector2Array([Vector2(0, vs.y - w), Vector2(vs.x, vs.y - w), vs, Vector2(0, vs.y)]), PackedColorArray([c1, c1, c0, c0]))
	ci.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, vs.y), Vector2(0, vs.y)]), PackedColorArray([c0, c1, c1, c0]))
	ci.draw_polygon(PackedVector2Array([Vector2(vs.x - w, 0), Vector2(vs.x, 0), vs, Vector2(vs.x - w, vs.y)]), PackedColorArray([c1, c0, c0, c1]))


## 击破一拍：0.6 秒缓慢褪去的白闪 + 名字一行「击破」
func _draw_outro(vs: Vector2, ci: CanvasItem) -> void:
	var t: float = outro.t
	var k: float = 1.0 - t / OUT_DUR
	var col: Color = outro.col
	ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.98, 0.96, 0.32 * k * k))
	var a: float = _ss(0.0, 0.08, t) * clampf(k * 1.6, 0.0, 1.0)
	var y0: float = maxf(vs.y * 0.36, g.hud_view.bars.boss_bottom + 60.0)
	var s := "%s · 击破" % outro.name
	var size: int = 26 if g.touch.active else 30
	var w: float = g.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	UI.fade_band(ci, Rect2(vs.x * 0.5 - w * 0.5 - 90.0, y0 - 26.0, w + 180.0, 50.0), Color(0.03, 0.035, 0.045, 0.7 * a), 100.0)
	UI.hairline(ci, Vector2(vs.x * 0.5, y0 + 20.0), Vector2(vs.x * 0.5 - w * 0.5 - 60.0, y0 + 20.0), col, 0.9 * a, 0.0)
	UI.hairline(ci, Vector2(vs.x * 0.5, y0 + 20.0), Vector2(vs.x * 0.5 + w * 0.5 + 60.0, y0 + 20.0), col, 0.9 * a, 0.0)
	UI.text(ci, g.font, Vector2(0, y0 + 10.0), s, size, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
	UI.en(ci, g.font, Vector2(vs.x * 0.5 - 34.0, y0 + 38.0), "DEFEATED", 12, Color(col.r, col.g, col.b, a), 3.0)


## 最终 Boss 击破演出（真实时间 t，0–FIN_DUR）：白闪褪去、黑边、结局色洗色 + 暗角、名片「名字 · 击破 / DEFEATED」+ 结局名
func _draw_finale(vs: Vector2, ci: CanvasItem) -> void:
	var t: float = float(finale.t)
	var col: Color = finale.col      # 结局色（洗色、黑边细线、结局名）
	var bcol: Color = finale.bcol    # Boss 强调色（名片细线）
	var low: bool = Cfg.quality == "low"
	var touch: bool = g.touch.active
	# 白闪：0.6 秒缓慢褪去（和普通击破一拍相同的一记）
	var kf: float = clampf(1.0 - t / 0.6, 0.0, 1.0)
	if kf > 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.98, 0.96, 0.32 * kf * kf))
	# 结局色洗色 + 暗角（低画质不画；去色在 post.gdshader，update 里按同一包络写）
	var env: float = _fin_env(t)
	if not low and env > 0.01:
		ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(col.r, col.g, col.b, 0.16 * env))
		ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.01, 0.02, 0.22 * env))
		_edge_glow(ci, vs, Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.5 * env), 170.0)
	# 黑边：0–0.25 滑入，末 0.3 滑出（触屏薄一点）；内缘结局色细线
	var kb: float = _ss(0.0, BAR_T, t) * (1.0 - _ss(FIN_DUR - 0.3, FIN_DUR, t))
	var bh: float = vs.y * (0.085 if touch else 0.12) * kb
	if bh > 0.5:
		ci.draw_rect(Rect2(0, 0, vs.x, bh), Color(0.01, 0.012, 0.02, 1.0))
		ci.draw_rect(Rect2(0, vs.y - bh, vs.x, bh), Color(0.01, 0.012, 0.02, 1.0))
		var lk: float = _ss(0.1, 0.5, t)
		for yy in [bh, vs.y - bh]:
			UI.hairline(ci, Vector2(vs.x / 2.0, yy), Vector2(vs.x / 2.0 - vs.x * 0.5 * lk, yy), col, 0.9 * kb, 0.0)
			UI.hairline(ci, Vector2(vs.x / 2.0, yy), Vector2(vs.x / 2.0 + vs.x * 0.5 * lk, yy), col, 0.9 * kb, 0.0)
	# 名片：0.25 起淡入，末 0.35 淡出
	var a: float = _ss(0.25, 0.5, t) * (1.0 - _ss(FIN_DUR - 0.35, FIN_DUR - 0.1, t))
	if a <= 0.01:
		return
	var slide: float = (1.0 - _ss(0.25, 0.6, t)) * 10.0
	var y0: float = maxf(vs.y * 0.36, g.hud_view.bars.boss_bottom + 60.0) - slide
	var s := "%s · 击破" % str(finale.name)
	var size: int = 30 if touch or vs.y < 680 else 36
	var font: Font = g.font
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	UI.fade_band(ci, Rect2(vs.x * 0.5 - w * 0.5 - 110.0, y0 - 34.0, w + 220.0, 96.0), Color(0.03, 0.035, 0.045, 0.72 * a), 120.0)
	UI.hairline(ci, Vector2(vs.x * 0.5, y0 + 24.0), Vector2(vs.x * 0.5 - w * 0.5 - 80.0, y0 + 24.0), bcol, 0.9 * a, 0.0)
	UI.hairline(ci, Vector2(vs.x * 0.5, y0 + 24.0), Vector2(vs.x * 0.5 + w * 0.5 + 80.0, y0 + 24.0), bcol, 0.9 * a, 0.0)
	UI.text(ci, font, Vector2(0, y0 + 12.0), s, size, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
	var en := "DEFEATED  ·  " + str(finale.en)
	var ew: float = UI.en_width(font, en, 12, 3.0)
	UI.en(ci, font, Vector2(vs.x * 0.5 - ew * 0.5, y0 + 44.0), en, 12, Color(bcol.r, bcol.g, bcol.b, a), 3.0)
	# 结局名（0.6 起，结局色小字）：这局走向哪个结局
	var la: float = a * _ss(0.6, 0.9, t)
	if la > 0.01:
		UI.text(ci, font, Vector2(0, y0 + 70.0), g.endg.cur_name(), 14, Color(col.r * 1.1, col.g * 1.1, col.b * 1.1, la), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
