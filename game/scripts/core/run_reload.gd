extends Node
## 手机网页局与局之间整页重载（11-08 用户定，docs/319 §14）：WASM 堆只涨不缩，同页连开第二局时开局就叠在上一局撑大的堆上
## （iPhone 第二局 1:52 被系统杀页）。结算页「再来一局」/「回标题」（及暂停菜单的重开 / 回标题）在手机网页上改成：
##   1) 立刻盖上与加载页同底色的盖层（不露白、不露空画布）；
##   2) 卸掉对局场景（照常走 game._exit_tree：本局记录、性能报告、崩溃前快照记 end，所以重载不会被判成异常退出）；
##   3) 存档落盘：Cfg.save() 后等云存档同步完（最多 CLOUD_WAIT 秒；本地已存好，没传完下次启动照常比对上传），
##      再等 IDBFS 写回 IndexedDB（engine_patch §6 __syFsSync）；
##   4) location.reload()。sessionStorage 里留一条 sy_reload：加载页读完直接开始（不再要一次「开始游戏」，loader.js），
##      标题页 resume() 读到「再来一局」就用同一名队长、同一难度直接出发（标题页的载入页），读到「认知塑造」/「寻访」就打开那一页
##      （11-09 用户：局后直接进认知塑造 iPhone 内存崩溃，结算页的这两个出口也走整页重载），读到「回标题」就停在标题页。
## 电脑网页 / 桌面包不变；测试局（带命令行参数）不重载，--runreload 强制开；--bal=web/mobile_run_reload=0 退回旧路径。
const KEY := "sy_reload"
const CLOUD_WAIT := 10.0
const FS_WAIT_MS := 4000
const GIVE_UP := 22.0     # 盖上底色后这么久页面还在（reload 被拦 / 没生效）：撤掉底色、改走普通回标题，并记进崩溃快照（11-09 B站 App 真机卡在底色上）

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
var gen=window.__syRLGen=(window.__syRLGen||0)+1;window.__syRLTry=0;window.__syRLFail='';var d=document.createElement('div');d.id='sy-rl';
d.style.cssText='position:fixed;inset:0;z-index:2147483647;background:radial-gradient(ellipse at 50%% 50%%,#0d1820 0%%,#070c11 70%%,#04070a 100%%)';
document.documentElement.style.background='#04070a';(document.body||document.documentElement).appendChild(d);
window.__syRLGo=function(why){if(window.__syRLTry)return;window.__syRLTry=why||'go';var h=location.href;
try{location.reload()}catch(e){}
setTimeout(function(){try{location.replace(h)}catch(e){}},2500);
setTimeout(function(){try{location.href=h.split('#')[0]+(h.indexOf('?')<0?'?':'&')+'_rl='+Date.now()}catch(e){}},5500);
setTimeout(function(){window.__syRLFail='reload 不生效';},9000)};
setTimeout(function(){if(window.__syRLGen===gen&&!window.__syRLTry){window.__syRLGo('watchdog')}},%d);
setTimeout(function(){if(window.__syRLGen!==gen)return;var c=document.getElementById('sy-rl');if(c)c.remove();window.__syRLFail=window.__syRLFail||'超时'},%d)})(%s)""" % [KEY, int((GIVE_UP + 4.0) * 1000), int((GIVE_UP + 16.0) * 1000), JSON.stringify(it)], true)
	var n = load("res://scripts/core/run_reload.gd").new()
	n.act = what
	n.name = "RunReload"
	n.process_mode = Node.PROCESS_MODE_ALWAYS   # 不受暂停影响
	g.get_tree().root.add_child(n)
	if not Cfg.dev_args().is_empty():
		print("PF RUNRELOAD go act=%s op=%s" % [what, Cfg.character_id])
	# 延后卸载：结算页按钮的回调还在对局场景里执行，当场 memdelete 对局场景 = 释放正在执行的对象（11-09 B站 App 真机：盖上底色后整页不动）
	g.get_tree().unload_current_scene.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	if _step >= 2:
		var f = JavaScriptBridge.eval("window.__syRLFail||''", true)
		if (f != null and str(f) != "") or _t > GIVE_UP + 14.0:
			_give_up(str(f) if f != null and str(f) != "" else "超时")
		return
	if _t > GIVE_UP:
		_give_up("云存档 / 存档同步没在 %d 秒内结束" % int(GIVE_UP))
		return
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
	if Cfg.dev_args().has("--rlblock"):   # 测试：模拟 WebView 拦掉重载，走兜底
		JavaScriptBridge.eval("window.__syRLGo=function(){window.__syRLTry=1;setTimeout(function(){window.__syRLFail='测试：reload 被拦'},1000)}", true)
	# 依次试 reload → replace(当前网址) → 带随机参数的网址（某些 WebView 不认 reload），都不生效时 __syRLFail 置位，_process 走兜底
	JavaScriptBridge.eval("""(function(){var done=false;function go(){if(done)return;done=true;window.__syRLGo('reload')}
setTimeout(go,%d);Promise.resolve(window.__syFsSync?window.__syFsSync():null).catch(function(){}).then(go)})()""" % FS_WAIT_MS, true)


## 兜底：页面没被替换。撤掉底色和 sessionStorage 标记，照旧路径回标题（不重载），记进崩溃快照
func _give_up(why: String) -> void:
	_step = 3
	set_process(false)
	print("PF RUNRELOAD giveup %s t=%.1f" % [why, _t])
	JavaScriptBridge.eval("(function(){window.__syRLTry='giveup';var c=document.getElementById('sy-rl');if(c)c.remove();try{sessionStorage.removeItem('%s')}catch(e){}})()" % KEY, true)
	load("res://scripts/core/crash_box.gd").note_reload_fail(why)
	get_tree().change_scene_to_file("res://main.tscn")
	queue_free()


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
	if not ["restart", "meta", "hunt"].has(str(d.get("act", ""))):
		return {}   # 回标题：停在标题页
	return d
