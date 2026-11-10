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


## 最多保留当前、上一个会话，各 24 条。只在阶段变化时落盘。
const JOURNEY_LIMIT := 24
static var _journey := {}
static var _previous := {}
static var _journey_owner := 0


static func _stored(name: String, tab := false) -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var raw = JavaScriptBridge.eval("(()=>{try{return %s.getItem('%s')||''}catch(e){return ''}})()" % ["sessionStorage" if tab else "localStorage", name], true)
	if not raw is String or raw.length() > 8192:
		return {}
	var d = JSON.parse_string(raw) if not raw.is_empty() else null
	if not d is Dictionary or not d.get("session") is String or not d.get("events") is Array or d.events.size() > JOURNEY_LIMIT:
		return {}
	for e in d.events:
		if not e is Dictionary or not e.get("kind") is String or not e.get("at") is float or not e.get("run") is float or not e.get("page") is float:
			return {}
	if not d.get("run") is float or not d.get("page") is float:
		return {}
	return d


static func _save_journey() -> void:
	if OS.has_feature("web"):
		var data := JSON.stringify(_journey)
		JavaScriptBridge.eval("(()=>{const d=%s;try{sessionStorage.setItem('sy_journey',d)}catch(e){}try{localStorage.setItem('sy_journey',d)}catch(e){}})()" % JSON.stringify(data), true)


static func _start_page(intent: Dictionary = {}, scoped := false) -> void:
	if not _journey.is_empty():
		return
	var tab := _stored("sy_journey", true)
	var last := _stored("sy_journey")
	_previous = _stored("sy_journey_prev")
	# WebView 某一页禁用 sessionStorage，下一页又恢复时，标签内可能还留着已用过的旧请求与旧页号。
	if not tab.is_empty() and last.get("session") == tab.session and int(last.page) > int(tab.page):
		tab = last
	var nav := ""
	if OS.has_feature("web"):
		nav = str(JavaScriptBridge.eval("performance.getEntriesByType('navigation')[0]?.type||''", true))
	var phase := "new_session"
	for d in [tab, last]:
		if not scoped or d.is_empty() or d.session != intent.get("journey_session", "") or d.events.is_empty():
			continue
		var tail: Dictionary = d.events.back()
		if tail.kind == "reload_request" and tail.get("action") == intent.get("act") and int(tail.page) == int(intent.get("journey_page", -1)) and int(tail.run) == int(intent.get("journey_run", -1)):
			_journey = d
			phase = "restored"
			break
	if _journey.is_empty() and intent.is_empty() and not tab.is_empty() and nav in ["reload", "back_forward"]:
		_journey = tab
		phase = "page_refresh" if nav == "reload" else "page_back"
	if _journey.is_empty():
		if not last.is_empty() and int(last.run) > 0:
			_previous = last
			JavaScriptBridge.eval("try{localStorage.setItem('sy_journey_prev',%s)}catch(e){}" % JSON.stringify(JSON.stringify(last)), true)
		_journey = {"session": Crypto.new().generate_random_bytes(8).hex_encode(), "run": 0, "page": 0, "events": []}
		if not intent.is_empty():
			phase = "unlinked_reload"
		elif nav in ["reload", "back_forward"]:
			phase = "unlinked_page"
	_journey.page = int(_journey.page) + 1
	_journey["page_origin"] = phase
	_journey["on_page"] = 0
	mark_stage(phase)


static func mark_stage(kind: String, action := "") -> void:
	if _journey.is_empty():
		_start_page()
	var e := {"kind": kind, "run": int(_journey.run), "page": int(_journey.page), "at": int(Time.get_unix_time_from_system())}
	if kind == "run_start":
		e["origin"] = _journey.page_origin
		e["on_page"] = _journey.on_page
		_journey["last_start"] = e.duplicate()
	if not action.is_empty():
		e["action"] = action
	_journey.events.append(e)
	if _journey.events.size() > JOURNEY_LIMIT:
		_journey.events.pop_front()
	_save_journey()


static func begin_run(g) -> void:
	if g.demo_op != "" or g.trial.active or _journey_owner == g.get_instance_id():
		return
	_start_page()
	_journey_owner = g.get_instance_id()
	_journey.run = int(_journey.run) + 1
	_journey.on_page = int(_journey.on_page) + 1
	mark_stage("run_start")


static func run_identity() -> Dictionary:
	if _journey.is_empty() or int(_journey.run) == 0:
		return {}
	return {"session": _journey.session, "run": int(_journey.run)}


static func journey_snapshot(identity: Dictionary = {}) -> Dictionary:
	var number := int(identity.get("run", 0))
	if number < 1 or not identity.get("session") is String:
		return {}
	for d in [_journey, _previous]:
		if d.is_empty() or d.session != identity.session:
			continue
		var events: Array = d.events
		var selected := []
		var start: Dictionary = d.get("last_start", {})
		if int(start.get("run", -1)) != number:
			start = {}
		for i in events.size():
			var e: Dictionary = events[i]
			if int(e.run) == number:
				if e.kind == "run_start":
					start = e
					if i > 0:
						selected.append(events[i - 1].duplicate())
				selected.append(e.duplicate())
			elif not selected.is_empty() and int(e.run) == number + 1:
				if e.kind == "run_start":
					selected.append(e.duplicate())
				break
		if not selected.is_empty():
			return {"session": d.session, "run": number, "page": int(start.get("page", 0)), "page_origin": start.get("origin", ""), "on_page": int(start.get("on_page", 0)), "events": selected}
	return {}


static func journey_lines(identity: Dictionary, fallback: Dictionary = {}) -> PackedStringArray:
	if identity.is_empty():
		return []
	var d := journey_snapshot(identity)
	if d.is_empty() and fallback.get("session") == identity.get("session") and int(fallback.get("run", -1)) == int(identity.get("run", 0)) and fallback.get("events") is Array:
		d = fallback
	if d.is_empty():
		return []
	var labels := {"new_session":"新会话（未关联上页）", "unlinked_page":"刷新或返回（前页未知）", "unlinked_reload":"重载恢复（前页未知）", "restored":"整页重载已恢复", "page_refresh":"标签页刷新", "page_back":"浏览器历史恢复", "title_ready":"标题就绪", "run_start":"开局", "settled":"结算", "reload_request":"请求重载", "reload_failed":"重载失败，返回标题", "hunt_open":"寻访打开"}
	var acts := {"hunt":"寻访", "title":"标题", "meta":"认知塑造", "restart":"再来一局"}
	var source: Dictionary = d
	if d.get("page_origin", "") == "" and fallback.get("session") == d.session and int(fallback.get("run", -1)) == int(d.run):
		source = fallback
	var origin := str(source.get("page_origin", ""))
	var explanation := str(labels.get(origin, "前页关联不足"))
	if int(source.get("on_page", 0)) > 1:
		explanation = "同页再开，本页第 %d 局" % int(source.on_page)
	elif origin == "new_session":
		explanation = "新会话首局（未关联上页）"
	elif origin == "restored":
		explanation = "局间重载后，本页首局"
	var out := PackedStringArray(["会话 %s · 第 %d 局 · %s" % [d.session, int(identity.run), explanation]])
	for e in d.events:
		var time := Time.get_time_string_from_unix_time(int(e.at))
		var act := str(acts.get(e.get("action", ""), ""))
		var run := "局前" if int(e.run) == 0 else "第%d局" % int(e.run)
		out.append("%s UTC · 页%d · %s · %s%s" % [time, int(e.page), run, labels.get(e.kind, e.kind), " / " + act if not act.is_empty() else ""])
	return out


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
	mark_stage("reload_request", what)
	var it := {"act": what, "op": Cfg.character_id, "diff": Cfg.difficulty}
	it["journey_session"] = _journey.session
	it["journey_page"] = _journey.page
	it["journey_run"] = _journey.run
	JavaScriptBridge.eval("""(function(it){var j='';if(window.__syRL){j=window.__syRL.put(it)}else{try{it.t=Date.now();j=JSON.stringify(it);sessionStorage.setItem('%s',j);localStorage.setItem('%s',j)}catch(e){}}
window.__syRLUrl=function(extra){var u=location.href.split('#')[0].replace(/([?&])(syrl|_rl)=[^&]*/g,'$1').replace(/[?&]+$/,'');return u+(u.indexOf('?')<0?'?':'&')+'syrl='+encodeURIComponent(j)+(extra||'')};
try{var bb=JSON.parse(localStorage.getItem('sy_bb')||'null');if(bb&&!bb.end){bb.end='reload';try{localStorage.setItem('sy_bb',JSON.stringify(bb))}catch(e2){localStorage.removeItem('sy_bb')}}}catch(e){}
var gen=window.__syRLGen=(window.__syRLGen||0)+1;window.__syRLTry=0;window.__syRLFail='';var d=document.createElement('div');d.id='sy-rl';
d.style.cssText='position:fixed;inset:0;z-index:2147483647;background:#000308 url(rl_bg.png) center/cover no-repeat;image-rendering:pixelated';
var sh=document.createElement('div');sh.style.cssText='position:absolute;inset:0;background:radial-gradient(ellipse at 50%% 50%%,rgba(0,3,8,.45) 25%%,rgba(0,3,8,.85) 100%%)';d.appendChild(sh);
document.documentElement.style.background='#04070a';(document.body||document.documentElement).appendChild(d);
window.__syRLGo=function(why){if(window.__syRLTry)return;window.__syRLTry=why||'go';
try{location.replace(window.__syRLUrl())}catch(e){try{location.reload()}catch(e2){}}
setTimeout(function(){try{location.reload()}catch(e){}},2500);
setTimeout(function(){try{location.href=window.__syRLUrl('&_rl='+Date.now())}catch(e){}},5500);
setTimeout(function(){window.__syRLFail='reload 不生效';},9000)};
setTimeout(function(){if(window.__syRLGen===gen&&!window.__syRLTry){window.__syRLGo('watchdog')}},%d);
setTimeout(function(){if(window.__syRLGen!==gen)return;var c=document.getElementById('sy-rl');if(c)c.remove();window.__syRLFail=window.__syRLFail||'超时'},%d)})(%s)""" % [KEY, KEY, int((GIVE_UP + 4.0) * 1000), int((GIVE_UP + 16.0) * 1000), JSON.stringify(it)], true)
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
	mark_stage("reload_failed", act)
	_step = 3
	set_process(false)
	print("PF RUNRELOAD giveup %s t=%.1f" % [why, _t])
	JavaScriptBridge.eval("(function(){window.__syRLTry='giveup';var c=document.getElementById('sy-rl');if(c)c.remove();if(window.__syRL){window.__syRL.take()}else{try{sessionStorage.removeItem('%s');localStorage.removeItem('%s')}catch(e){}}})()" % [KEY, KEY], true)
	load("res://scripts/core/crash_box.gd").note_reload_fail(why)
	get_tree().change_scene_to_file("res://main.tscn")
	queue_free()


## 标题页 _ready：重载回来时读掉 sy_reload。「再来一局」返回 {op, diff}（标题页照此直接出发），其余返回空
static func resume() -> Dictionary:
	if not OS.has_feature("web"):
		_start_page()
		return {}
	# 三处任读一处（loader.js window.__syRL：sessionStorage / localStorage / 网址参数 syrl，3 分钟内有效），读完三处都清、网址参数去掉
	var r = JavaScriptBridge.eval("""(()=>{
let tab=null,url=null;
try{tab=JSON.parse(sessionStorage.getItem('sy_reload'))}catch(e){}
try{url=JSON.parse(new URLSearchParams(location.search).get('syrl'))}catch(e){}
let o=null;
try{if(window.__syRL){o=window.__syRL.take()}else{o=tab;sessionStorage.removeItem('sy_reload')}}catch(e){}
if(!o)return '';
const scoped=[tab,url].some(v=>v&&v.t===o.t&&v.act===o.act&&v.journey_session===o.journey_session&&v.journey_page===o.journey_page&&v.journey_run===o.journey_run);
return JSON.stringify({intent:o,scoped:scoped&&Date.now()>=o.t&&Date.now()-o.t<180000})})()""", true)
	var envelope = JSON.parse_string(str(r)) if r != null and str(r) != "" else null
	var d = envelope.get("intent") if envelope is Dictionary else null
	_start_page(d if d is Dictionary else {}, envelope is Dictionary and envelope.get("scoped") == true)
	if not d is Dictionary:
		return {}
	if not Cfg.dev_args().is_empty():
		print("PF RUNRELOAD resume act=%s" % str(d.get("act", "")))
	if not ["restart", "meta", "hunt"].has(str(d.get("act", ""))):
		return {}   # 回标题：停在标题页
	return d
