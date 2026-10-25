## 原生模块薄封装（docs/101 §4.7）：ark_native GDExtension 在（ClassDB 里有这个类）才实例化，否则返回 null，调用方走 GDScript 路径。
## 没有 dll 的机器（网页、云端、别人的工作树）与 --optold=131072（OPT_CPP）时行为与纯 GDScript 版逐位相同。
extends RefCounted

static var _core = null
static var _core_checked := false


## 敌人运动核心 EnemyCore（run/enemies.gd 的 _motion_core 的原生版）；没有扩展返回 null
static func enemy_core():
	if not _core_checked:
		_core_checked = true
		if ClassDB.class_exists("EnemyCore"):
			_core = ClassDB.instantiate("EnemyCore")
	return _core


## 敌人绘制 EnemyRender（render/world.gd 排序实体 / 影子 / 发光点的原生版，docs/50 §30）；没有扩展返回 null。
## 每个世界各建一个（不共用：图鉴 / 精英化演出里内嵌的演示局另有一个世界，共用会串发光点缓冲与种类登记）
static func enemy_render():
	if ClassDB.class_exists("EnemyRender"):
		return ClassDB.instantiate("EnemyRender")
	return null
