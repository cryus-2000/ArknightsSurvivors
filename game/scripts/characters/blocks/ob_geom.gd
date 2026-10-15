## 干员积木的几何判定（B6 ⑤，docs/101 §7.3.4 / §7.3.9）：纯函数，只判「敌人圆心 p、半径 r 碰不碰得到这个形状」，不查询、不改状态。
## 继承链最底层（ob_core extends 本文件），所以各段不加前缀就能调。算式照抄各处原来的内联写法（同 seed 逐行不变），改算式要单独一步换基线。
## 胶囊（德克萨斯冲刺斩 / 推进之王破阵地裂 / 流明光束三处算式各不相同）不在这里，归 B7 换基线时合一。
extends RefCounted


## 有向矩形：从 origin 沿单位向量 d 长 L、横向半宽 half_w（全宽的一半）；沿线 [-r, L + r]、横向 ≤ half_w + r
static func seg_rect(origin: Vector2, d: Vector2, L: float, half_w: float, p: Vector2, r: float) -> bool:
	var rel: Vector2 = p - origin
	var along: float = rel.dot(d)
	if along < -r or along > L + r:
		return false
	return absf(rel.cross(d)) <= half_w + r


## 同 seg_rect，另返回沿线距离（命中按远近排序用）；没碰到返回 -INF
static func seg_rect_along(origin: Vector2, d: Vector2, L: float, half_w: float, p: Vector2, r: float) -> float:
	var rel: Vector2 = p - origin
	var along: float = rel.dot(d)
	if along < -r or along > L + r or absf(rel.cross(d)) > half_w + r:
		return -INF
	return along


## 线段判定（老名字，W = 全宽；测试与各段照旧调）
static func line_contains(origin: Vector2, d: Vector2, L: float, W: float, p: Vector2, er: float) -> bool:
	return seg_rect(origin, d, L, W * 0.5, p, er)


## 以 c 为中心、沿单位向量 d 前后各 half_len、横向（d.orthogonal()）各 half_w 的框
static func box_centered(c: Vector2, d: Vector2, half_len: float, half_w: float, p: Vector2, r: float) -> bool:
	var rel: Vector2 = p - c
	return absf(rel.dot(d)) <= half_len + r and absf(rel.dot(d.orthogonal())) <= half_w + r
