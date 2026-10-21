extends RefCounted
## 全员共用「撤退」表现（10-21 用户定，替代逐人 death 条）：叠在干员当前帧上，参照原作撤退——
##   0–FLASH 秒：整体提白闪；之后 FADE 秒内向上收窄（横向收、纵向略拉长）、提白并透明消散；同时白色碎光从身上上飘。
## 纯画面：不读写玩法状态，碎光位置由序号算（不用随机数），同 seed 不变。
## 用在：队长倒下（character.draw_body，按 g.state_age）、队友离队 / 换人（squad.remove 留下 g.fx kind "retreat"）、图鉴「撤退」形态。

const A = preload("res://scripts/art.gd")
const FLASH := 0.12
const FADE := 0.4
const TOTAL := FLASH + FADE + 0.25   # 碎光比本体多飘 0.25 秒
const MOTES := 12


## 在 ci（世界画布）上画一帧撤退。st = anim_state() 快照（tex / frame / hf / flip），foot = 脚底世界坐标，foot_off = 帧条脚底偏移，age = 已播秒数
static func draw(ci: CanvasItem, st: Dictionary, foot: Vector2, foot_off: float, age: float, px: float, mod := Color.WHITE) -> void:
	if age >= TOTAL or st.is_empty():
		return
	var tx: Texture2D = st.get("tex", null)
	if tx != null and age < FLASH + FADE:
		var hf: int = maxi(1, int(st.get("hf", 1)))
		var fw: int = tx.get_width() / hf
		var fh: int = tx.get_height()
		var src := Rect2(fw * (int(st.get("frame", 0)) % hf), 0, fw, fh)
		var pk: float = px / A.hires_of(tx)
		var col: Color
		var sx := 1.0
		var sy := 1.0
		if age < FLASH:
			var k: float = age / FLASH
			col = Color(1.0 + 2.2 * k, 1.0 + 2.2 * k, 1.0 + 2.2 * k, 1.0)   # 渐亮到提白
		else:
			var k: float = (age - FLASH) / FADE
			var e: float = k * k
			sx = 1.0 - 0.75 * e
			sy = 1.0 + 0.25 * e
			col = Color(3.2, 3.2, 3.4, 1.0 - k)
		col *= mod
		var flip: bool = st.get("flip", false)
		ci.draw_set_transform(foot.round(), 0.0, Vector2((-pk if flip else pk) * sx, pk * sy))
		ci.draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh + foot_off), Vector2(fw, fh)), src, col)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 白色碎光：从身体高度带里冒出、上飘、横向轻摆、渐隐（按序号定位，不用随机）
	if age < FLASH * 0.5:
		return
	var body_h: float = 30.0 * px / 2.0 if tx == null else float(tx.get_height()) / A.hires_of(tx) * px * 0.8
	for i in MOTES:
		var t0: float = FLASH * 0.5 + 0.03 * float(i % 6)
		var a: float = age - t0
		if a < 0.0:
			continue
		var life: float = 0.45 + 0.05 * float(i % 4)
		if a > life:
			continue
		var u: float = a / life
		var hx: float = sin(float(i) * 2.39996) * 9.0 * px / 2.0
		var hy: float = -body_h * (0.15 + 0.7 * fmod(float(i) * 0.618034, 1.0))
		var p: Vector2 = foot + Vector2(hx + sin(u * 6.0 + float(i)) * 2.0, hy - u * (22.0 + 6.0 * float(i % 3)) * px / 2.0)
		var s: float = (2.0 if i % 3 == 0 else 1.0) * px / 2.0
		ci.draw_rect(Rect2(p.round() - Vector2(s, s) * 0.5, Vector2(s, s)), Color(2.4, 2.4, 2.6, (1.0 - u) * 0.95) * mod)
