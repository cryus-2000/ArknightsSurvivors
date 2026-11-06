extends RefCounted
## 网页版全屏与 Esc（11-06 用户「itch 全屏之后一按 esc 就会退出全屏，修复一下」，docs/297）。
## 浏览器全屏下 Esc 由浏览器拿去退出全屏，网页拦不住；只有顶层页面自己请求的全屏能用 Keyboard Lock 锁住 Esc
## （Chrome / Edge；锁住后短按 Esc 照常进页面 = 暂停，长按才退出全屏）。itch 把游戏放在 iframe 里，锁不住，所以兜底：
## 1. 局内因为退出全屏（多半就是按了 Esc）→ 当作暂停，直接打开暂停菜单；
## 2. 暂停菜单里给「返回全屏」（点击 / 按 F 属于用户手势，可以重新请求全屏）；
## 3. P 键也能暂停 / 继续（全屏时用它不会退出全屏），暂停菜单里写明。
## 只在网页版桌面生效（手机 / 触屏、Windows 包、无头测试都不装），不碰对局逻辑。

const UI = preload("res://scripts/ui.gd")
const POLL := 0.25

var g = null
var on := false          # 网页版桌面
var back := false        # 这次暂停是退出全屏引起的：暂停菜单显示「返回全屏」
var _exit_seen := 0
var _pend := false       # 选卡 / 商店 / 动画等非对局状态下退出了全屏：回到对局时补一次暂停
var _t := 0.0
var btn := Rect2()       # 「返回全屏」按钮命中区（UI 坐标；没画时为空）

const JS_SETUP := """(function(){if(window.__syFs)return;var F=window.__syFs={was:false,exit:0,lock:-1};
function el(){return document.fullscreenElement||document.webkitFullscreenElement;}
function full(){return !!el()||(Math.abs(innerWidth-screen.width)<=2&&Math.abs(innerHeight-screen.height)<=2);}
function upd(){var f=full();
 if(f&&!F.was){F.was=true;F.lock=0;
  if(el()&&window.top===window&&navigator.keyboard&&navigator.keyboard.lock){navigator.keyboard.lock(['Escape']).then(function(){F.lock=1},function(){F.lock=0});}}
 else if(!f&&F.was){F.was=false;F.exit++;try{if(navigator.keyboard&&navigator.keyboard.unlock)navigator.keyboard.unlock();}catch(e){}}}
document.addEventListener('fullscreenchange',upd);document.addEventListener('webkitfullscreenchange',upd);addEventListener('resize',upd);upd();
F.req=function(){var d=document.documentElement,r=d.requestFullscreen||d.webkitRequestFullscreen;if(!r)return;try{var p=r.call(d);if(p&&p.catch)p.catch(function(){});}catch(e){}};
F.full=full;})()"""


func setup(game) -> void:
	g = game
	on = OS.has_feature("web") and not Cfg.touch_device()
	if not on:
		return
	JavaScriptBridge.eval(JS_SETUP, true)
	_exit_seen = int(JavaScriptBridge.eval("window.__syFs?window.__syFs.exit:0", true))


func poll(delta: float) -> void:
	if not on:
		return
	_t += delta
	if _t < POLL:
		return
	_t = 0.0
	var n := int(JavaScriptBridge.eval("window.__syFs?window.__syFs.exit:0", true))
	if n != _exit_seen:
		_exit_seen = n
		_pend = not is_full()   # 已经又全屏了（比如 F11 来回）就不算
	elif g.state == g.S.PLAY:
		back = false   # 回到对局就收起「返回全屏」
	if not _pend:
		return
	if g.state == g.S.PLAY:
		g.state = g.S.PAUSE   # 全屏下按 Esc 的本意就是暂停
		back = true
		_pend = false
	elif g.state == g.S.PAUSE:
		back = true
		_pend = false
	elif g.state == g.S.DEAD or g.state == g.S.WIN:
		_pend = false


func is_full() -> bool:
	return on and bool(JavaScriptBridge.eval("window.__syFs?window.__syFs.full():false", true))


func request() -> void:
	if on:
		JavaScriptBridge.eval("window.__syFs&&window.__syFs.req()", true)
		back = false


## P 键当 Esc 用的暂停 / 继续（只在网页版桌面）
func pause_key(k: int) -> bool:
	return on and k == KEY_P


## 暂停菜单下方：一行说明 +（退出全屏引起的暂停时）「返回全屏」按钮
func draw_pause(vs: Vector2) -> void:
	btn = Rect2()
	if not on:
		return
	var y: float = vs.y / 2 + 190 + 34
	UI.text(g.hud, g.font, Vector2(0, y), "全屏时 Esc 会退出全屏，可按 P 暂停 / 继续", 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if not back or is_full():
		return
	var lbl := "返回全屏"
	var w: float = UI.cwidth(g.font, lbl, 15) + 84.0
	btn = Rect2(vs.x / 2 - w / 2, y + 14, w, 38)
	var hov: bool = btn.has_point(g.hud.get_local_mouse_position())
	g.hud.draw_rect(btn, UI.CYAN if hov else Color(1, 1, 1, 0.04))
	g.hud.draw_rect(btn, Color(1, 1, 1, 0.28), false, 1.0)
	var ink: Color = Color(0.04, 0.07, 0.09) if hov else UI.TEXT
	UI.text(g.hud, g.font, btn.position + Vector2(14, 25), lbl, 15, ink)
	UI.keycap(g.hud, g.font, Vector2(btn.end.x - UI.cwidth(g.font, "F", 10) - 20, btn.position.y + 10), "F", ink, 10)
