## 手机网页局外界面闲置降帧（10-27 用户「手机发烫」，docs/50 §33）：标题页 / 图鉴 / 设置这些界面没人碰时照 30 帧整屏重画是空耗电。
## 挂在界面节点下：IDLE_AFTER 秒没有任何输入就降到 render/static_fps（缺省 20），一碰屏幕 / 按键立刻回到玩家的帧率上限。
## 只在手机网页、帧率设置为「自动」时生效；不吞输入（_input 里只记时间）。--bal=web/mobile_static_fps=0 退回
extends Node

const IDLE_AFTER := 2.0
var _idle := 0.0
var _on := false


func _ready() -> void:
	_on = Cfg.mobile_web() and Cfg.mobile_knob("mobile_static_fps", 1.0)
	set_process(_on)
	set_process_input(_on)


func _input(_e: InputEvent) -> void:
	_idle = 0.0
	if Engine.max_fps != Cfg.effective_max_fps() and Cfg.max_fps == 0:
		Engine.max_fps = Cfg.effective_max_fps()


func _process(delta: float) -> void:
	if Cfg.max_fps != 0:
		return
	_idle += delta
	var want: int = int(load("res://scripts/core/balance.gd").v("render/static_fps", 20.0)) if _idle > IDLE_AFTER else Cfg.effective_max_fps()
	if Engine.max_fps != want:
		Engine.max_fps = want


func _exit_tree() -> void:
	if _on and Cfg.max_fps == 0:
		Engine.max_fps = Cfg.effective_max_fps()   # 离开界面（进局）恢复，对局里由 game._static_fps 接管
