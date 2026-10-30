extends RefCounted
## 界面里的干员小人（10-30 用户「对局记录和作战记录里面人物大小不一致」）：作战记录（编队行 / 队长卡 / 详情身份卡）、对局记录、
## 结算（作战报告的队长立绘、旧版编队卡）、分享卡共用这一个画法。
## 原因：各处按「该帧条可见包围盒」取整数倍塞进框，可帧条画布不一样大——水月是 192 画布（伞 / 触须让包围盒高 101 贴图像素），
##   斯卡蒂·浊心高 99，其余 128 画布 75–82：同一个框里水月被压到低一档倍数，只有德克萨斯的一半左右高。
## 规则：所有干员按同一个比例画，以脚底（def.sprites.foot，没写取包围盒底边中点）对齐框底边中线；比例由框高定——
##   脚底往上 REF 个美术像素（48 画布的站立高 + 头饰，同 UI.op_win 口径）不超过框高，按 1/4 美术像素取档。
##   各干员本人在原作里的高矮差（几个美术像素）照实保留；超出框的部分（伞、大剑、触须）按 clip 裁掉，clip 缺省 = 框。
const A = preload("res://scripts/art.gd")

const REF := 46.0   # 脚底往上的参考站高（美术像素）


## 框高 h（屏幕像素）对应的「每美术像素几屏幕像素」：1/4 一档（@2x 帧条每贴图像素 1/8 屏幕像素一档），最少 0.5
static func k_for(h: float) -> float:
	return maxf(0.5, floorf(h / REF * 4.0) / 4.0)


## 画一帧：idle = choice_panel.op_idle(id)；frame = 第几帧；k_art < 0 时按框高取（k_for）。返回画出的矩形（已裁进 clip）
static func draw(ci: CanvasItem, idle: Dictionary, box: Rect2, frame := 0, mod := Color.WHITE, k_art := -1.0, clip := Rect2()) -> Rect2:
	if idle.is_empty() or box.size.y <= 2.0:
		return Rect2()
	var tx: Texture2D = idle.tex
	var fw: float = float(idle.fw)
	var fh: float = float(idle.fh)
	var hi: float = A.hires_of(tx)
	var bb: Rect2 = idle.get("bb", Rect2(0, 0, fw, fh))
	if not bb.has_area():
		bb = Rect2(0, 0, fw, fh)
	var ft = idle.get("foot")
	var foot := Vector2(bb.get_center().x, bb.end.y)   # 贴图像素
	if ft is Array and ft.size() >= 2:
		foot = Vector2(float(ft[0]), float(ft[1])) * hi
	var ka: float = k_art if k_art > 0.0 else k_for(box.size.y)
	var s: float = ka / hi   # 每贴图像素几屏幕像素
	var anchor := Vector2(roundf(box.get_center().x), roundf(box.end.y))
	var dst := Rect2(anchor + (bb.position - foot) * s, bb.size * s)
	var cl: Rect2 = clip if clip.has_area() else box
	var vis := dst.intersection(cl)
	if not vis.has_area():
		return Rect2()
	var src := Rect2(bb.position + (vis.position - dst.position) / s, vis.size / s)
	src.position.x += float(frame) * fw
	ci.draw_texture_rect_region(tx, vis, src, mod)
	return vis
