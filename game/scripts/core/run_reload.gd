extends Node
## 手机网页局与局之间整页重载（11-08 用户定，docs/319 §14）：WASM 堆只涨不缩，同页连开第二局时开局就叠在上一局撑大的堆上
## （iPhone 第二局 1:52 被系统杀页）。结算页「再来一局」/「回标题」（及暂停菜单的重开 / 回标题）在手机网页上改成：
##   1) 立刻盖上与加载页同底色的盖层（不露白、不露空画布）；
##   2) 卸掉对局场景（照常走 game._exit_tree：本局记录、性能报告、崩溃前快照记 end，所以重载不会被判成异常退出）；
##   3) 存档落盘：Cfg.save() 后等云存档同步完（最多 CLOUD_WAIT 秒；本地已存好，没传完下次启动照常比对上传），
##      再等 IDBFS 写回 IndexedDB（engine_patch §6 __syFsSync）；
##   4) location.reload()。sessionStorage 里留一条 sy_reload：加载页读完直接开始（不再要一次「开始游戏」，loader.js），
##      标题页 resume() 读到「再来一局」就用同一名队长、同一难度直接出发（标题页的载入页），读到「回标题」就停在标题页。
## 电脑网页 / 桌面包不变；测试局（带命令行参数）不重载，--runreload 强制开；--bal=web/mobile_run_reload=0 退回旧路径。
const KEY := "sy_reload"
const CLOUD_WAIT := 10.0
const FS_WAIT_MS := 4000

var act := ""
var _t := 0.0
var _step := 0
var _cloud_started := false


static func wanted(g) -> bool:
	if not OS.has_feature("web"):
		return false
	if g.demo_op != "" or g.trial.active:
		return false
	if Cfg.dev_args().has("--runreload"):
		return true
	if not Cfg.dev_args().is_empty():
		return false
	return Cfg.mobile_web() and Cfg.mobile_knob("mobile_run_reload", 1.0)


## game._do_action("restart" / "title") 在手机网页上改走这里
static func go(g, what: String) -> void:
	var it := {"act": what, "op": Cfg.character_id, "diff": Cfg.difficulty}
	JavaScriptBridge.eval("""(function(it){try{it.t=Date.now();sessionStorage.setItem('%s',JSON.stringify(it))}catch(e){}
var d=document.createElement('div');d.id='sy-rl';
d.style.cssText='position:fixed;inset:0;z-index:2147483647;background:radial-gradient(ellipse at 50%% 50%%,#0d1820 0%%,#070c11 70%%,#04070a 100%%)';
document.documentElement.style.background='#04070a';(document.body||document.documentElement).appendChild(d)})(%s)""" % [KEY, JSON.stringify(it)], true)
	var n = load("res://scripts/core/run_reload.gd").new()
	n.act = what
	n.name = "RunReload"
	g.get_tree().root.add_child(n)
	if not Cfg.dev_args().is_empty():
		print("PF RUNRELOAD go act=%s op=%s" % [what, Cfg.character_id])
	g.get_tree().unload_current_scene()


func _process(delta: float) -> void:
	_t += delta
	match _step:
		0:
			if _t < 0.05:
				return   # 等对局场景真正卸掉（_exit_tree 里写本局记录 / 报告 / 快照 end）
			Cfg.save()
			_step = 1
		1:
			if _cloud_done():
				_step = 2
				_reload()


func _cloud_done() -> bool:
	if not Cloud.active() or _t > CLOUD_WAIT:
		return true
	if Cloud._busy:
		_cloud_started = true
		return false
	if _cloud_started:
		return true   # 这一次同步已结束（成功 / 失败都走：本地已落盘，没传上去的下次启动比对上传）
	if not Cloud.pending():
		return true
	Cloud._timer = -1.0
	Cloud._start("sync")   # 不等去抖 / 最小间隔：读云端合并后上传，同结算时那一次
	_cloud_started = true
	return false


func _reload() -> void:
	if not Cfg.dev_args().is_empty():
		print("PF RUNRELOAD reload t=%.2f cloud=%s" % [_t, str(_cloud_started)])
	JavaScriptBridge.eval("""(function(){var done=false;function go(){if(done)return;done=true;location.reload()}
setTimeout(go,%d);Promise.resolve(window.__syFsSync?window.__syFsSync():null).catch(function(){}).then(go)})()""" % FS_WAIT_MS, true)


## 标题页 _ready：重载回来时读掉 sy_reload。「再来一局」返回 {op, diff}（标题页照此直接出发），其余返回空
static func resume() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var r = JavaScriptBridge.eval("(function(){try{var s=sessionStorage.getItem('%s');sessionStorage.removeItem('%s');return s||''}catch(e){return ''}})()" % [KEY, KEY], true)
	var d = JSON.parse_string(str(r)) if r != null and str(r) != "" else null
	if not d is Dictionary:
		return {}
	if not Cfg.dev_args().is_empty():
		print("PF RUNRELOAD resume act=%s" % str(d.get("act", "")))
	if str(d.get("act", "")) != "restart":
		return {}
	return d
