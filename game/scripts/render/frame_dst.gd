extends RefCounted
## 精灵取帧 + 落点（docs/101 B4 ②，§3.2 ④）：横排帧条「第几帧的源矩形」与「按锚点放、取整、以锚点为轴翻转」的唯一写法。
## vfx.spr / spr_on、EnemyAtlas.spr、map._spr、world._pq_sprite 都调这里；影子与经验结晶两处每帧几百次的热循环按同一算式内联（docs/50 §11）。
## 算式与原来各处手写的逐字相同（size × anchor 后取整；翻转 = 在 pos.round() 处 scale(-1, 1) 画 Rect2(-size × anchor, size)），像素不变。
## 纯静态、不 preload 别的脚本：谁 preload 它都不会形成 preload 环（导出 / 验包退出时的「resources still in use」）。
## 干员侧的帧条助手（character / 积木）归干员，接口见 docs/101a


## 横排帧条第 frame 帧的源矩形；origin 是帧条在图集里的左上角（独立贴图为 0）
static func src(fw: int, fh: int, frames: int, frame: int, origin := Vector2i.ZERO) -> Rect2:
	return Rect2(origin.x + fw * (frame % frames), origin.y, fw, fh)


## 以 anchor（帧内比例 0–1）对准 pos、取整后的目标矩形
static func dst(pos: Vector2, size: Vector2, anchor: Vector2) -> Rect2:
	return Rect2((pos - size * anchor).round(), size)


## 画一帧到 ci：不翻转画 dst(pos, size, anchor)；翻转时以锚点为轴水平镜像（变换用完复位成单位矩阵）
static func blit(ci: CanvasItem, tx: Texture2D, src_r: Rect2, pos: Vector2, size: Vector2, anchor: Vector2, flip: bool, col: Color) -> void:
	if flip:
		ci.draw_set_transform(pos.round(), 0.0, Vector2(-1, 1))
		ci.draw_texture_rect_region(tx, Rect2(-size * anchor, size), src_r, col)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		ci.draw_texture_rect_region(tx, dst(pos, size, anchor), src_r, col)
