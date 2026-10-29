## 镜头演出组合口（arch_review_1029 风险 2 / P1-1）：镜头缩放 = 设置给的基础缩放（Cfg.battle_zoom）× punch()。
## 各演出来源登记一次（add），每帧取最大（推得最近的那个）；没有来源 / 都是 1 时 punch() = 1，画面与原来逐像素相同。
## optical._lo_step 与 game._process 低档对齐两处都乘它；光学低分辨率画布在推镜期间只放大不缩小（不每帧重分配）。
## 网页版不推镜（画布重分配代价没在手机上量过，docs/198 §7.4 帧率约束）。纯画面：不碰随机数、不进模拟。
extends RefCounted

var g
var _src: Array = []   # [名字, Callable() -> float]


func _init(game) -> void:
	g = game


func add(owner: String, fn: Callable) -> void:
	remove(owner)
	_src.append([owner, fn])


func remove(owner: String) -> void:
	for i in range(_src.size() - 1, -1, -1):
		if _src[i][0] == owner:
			_src.remove_at(i)


func punch() -> float:
	if _src.is_empty() or OS.has_feature("web") or g.demo_op != "":
		return 1.0
	var k := 1.0
	for s in _src:
		k = maxf(k, float(s[1].call()))
	return k
