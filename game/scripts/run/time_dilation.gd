## 局内时间缩放的唯一所有者（arch_review_1029 风险 2 / P0-1）：各来源登记一次（add），game._process 每帧只乘 factor()。
## kind："play" = 玩法性（指挥圆盘、指点选点），批跑里也生效；"fx" = 演出性（终结技 / 连携终结技慢动作），
##   只在玩家局 / --realtime / --playclock 生效，机器人批跑跳过（同顿帧：演出不改模拟步长，结果可复现）。
## 叠加规则：同一帧多个来源取最小（不相乘）。顿帧（vfx.stop → g.hitstop）、最终 Boss 击破慢放（victory_flow）、
##   倒下过渡（defeat_outro）都是整段接管画面步长，不走这里。
extends RefCounted

var g
var _src: Array = []   # [名字, Callable() -> float, kind]


func _init(game) -> void:
	g = game


## 登记一个来源（同名重复登记 = 替换）；fn 返回本帧要的倍率（1 = 不缩放）
func add(owner: String, fn: Callable, kind := "play") -> void:
	remove(owner)
	_src.append([owner, fn, kind])


func remove(owner: String) -> void:
	for i in range(_src.size() - 1, -1, -1):
		if _src[i][0] == owner:
			_src.remove_at(i)


## visual：这一帧是不是看得见的局（玩家局 / --realtime / --playclock）；不是时只认 play 类
func factor(visual: bool) -> float:
	var f := 1.0
	for s in _src:
		if s[2] == "fx" and not visual:
			continue
		f = minf(f, float(s[1].call()))
	return f


## 当前生效的来源（调试 / 测试读）
func active(visual: bool) -> Array:
	var out: Array = []
	for s in _src:
		if (s[2] != "fx" or visual) and float(s[1].call()) < 1.0:
			out.append(s[0])
	return out
