extends Node
## B站 Toy 云存档（自动加载为 Cloud，docs/89）。只在网页版、页面里有 window.__syCloud（tools/web/cloud.js）、
## Toy SDK 在且 toy.isSupport('getCloudStorage') 为真、读云端成功（= 已登录）时工作；其余情况（桌面版、itch、普通浏览器、
## 自动测试、对内包全部解锁）什么都不做，存档照旧只在本地 settings.cfg。
##
## 流程：
##   启动：读一次云端（getCloudStorage 不带 key = 全部）→ 校验 → 与本地合并（core/cloud_pack.gd merge）→ 有变化写回本地 →
##        合并结果和云端不同就上传（一次 setCloudStorage 带全部分片）。
##   之后：Cfg.save() 只调 local_saved()：标「待上传」，并把打包好的内容交给网页（页面隐藏时 cloud.js 自己上传）；
##        真正联网只在 flush() 的时机：一局结算、回到标题、设置面板关闭。每次上传前先读云端再合并（另一台设备期间写过也不丢）。
##   失败：保留本地，留着「待上传」；307044 限流指数退避（5 秒起，翻倍，封顶 300 秒）；其他错误 60 秒起翻倍、封顶 600 秒。
##        启动时第一次读就失败（非限流）按「未登录」处理，本次运行不再请求（未登录的玩家不消耗全 Toy 共享的请求额度）。
##   云端校验失败 / 版本更新：不覆盖本地、不自动上传，状态行提示；设置里「从云端恢复 / 以本地覆盖云端」手动处理。
## 不读取 toyOpenId，也不调 getUserProfile（那个会弹数据确认框）。

signal changed   # 状态变了（设置面板重画状态行）

const Pack = preload("res://scripts/core/cloud_pack.gd")

enum St { OFF, PROBING, OFFLINE, SYNCING, SYNCED, PENDING, FAILED, BAD, NEWER }
const DEBOUNCE := 1.0        # 触发后等这么久再发（同一时刻的多个触发合成一次）
const MIN_GAP := 10.0        # 两次联网之间至少隔这么久（秒）
const RL_BASE := 5.0         # 307044 限流退避起点
const RL_MAX := 300.0
const ERR_BASE := 60.0       # 其他错误退避起点
const ERR_MAX := 600.0
const RATE_LIMIT := 307044

var st: int = St.OFF
var supported := false       # B站环境且支持云存储：设置里显示「存档」页
var err_text := ""           # 最近一次错误 / 校验失败的说明（日志与测试用，不直接给玩家看）
var msg := ""                # 手动操作的结果（状态行右侧短暂显示）
var msg_t := 0.0
var requests := 0            # 本次运行发出的请求数（测试用）

var _js = null
var _cb_probe = null
var _cb_get = null
var _cb_set = null
var _busy := false
var _again := false
var _mode := ""              # 进行中的操作："sync" / "pull" / "push"
var _up_sig := ""
var _timer := -1.0           # 计划中的同步时刻（_now() 秒）；-1 = 没有
var _next_ok := 0.0          # 下次最早可以联网的时刻
var _rl_n := 0               # 连续限流次数
var _err_n := 0              # 连续其他错误次数
var _ever_ok := false        # 本次运行读写成功过


func _ready() -> void:
	if not OS.has_feature("web") or Cfg.unlock_all:
		return
	for a in Cfg.dev_args():
		if a.begins_with("--"):
			return   # 自动测试不写玩家存档，也不碰云端
	_js = JavaScriptBridge.get_interface("__syCloud")
	if _js == null:
		return
	_cb_probe = JavaScriptBridge.create_callback(_on_probe)
	_cb_get = JavaScriptBridge.create_callback(_on_get)
	_cb_set = JavaScriptBridge.create_callback(_on_set)
	_set_st(St.PROBING)
	_js.probe(_cb_probe)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _set_st(s: int) -> void:
	st = s
	changed.emit()


func _log(t: String) -> void:
	print("[Cloud] " + t)


## 在线可用（已登录、云端格式可读）：可以自动同步
func active() -> bool:
	return st in [St.SYNCING, St.SYNCED, St.PENDING, St.FAILED]


## 手动入口可用（已登录）
func can_manual() -> bool:
	return st in [St.SYNCED, St.PENDING, St.FAILED, St.BAD, St.NEWER] and not _busy


func pending() -> bool:
	return Pack.sig(Cfg.cloud_body()) != Cfg.cloud_sig


## 设置里状态行的文字（docs/76：短、陈述）
func status_text() -> String:
	match st:
		St.PROBING, St.SYNCING:
			return "同步中"
		St.OFFLINE:
			return "未登录（仅本地保存）"
		St.SYNCED:
			return "待上传" if pending() else "已同步"
		St.PENDING:
			return "同步中" if _busy else "待上传"
		St.FAILED:
			return "上传失败，稍后重试"
		St.BAD:
			return "云端存档无法读取（仅本地保存）"
		St.NEWER:
			return "云端存档来自更新的版本（仅本地保存）"
	return ""


# ---------------------------------------------------------------- 触发

## Cfg.save() 之后：本地有改动就标待上传，并把打包结果交给网页（页面隐藏时上传）。不联网
func local_saved() -> void:
	if _js == null or not active() or _busy:
		return
	var body := Cfg.cloud_body()
	if Pack.sig(body) == Cfg.cloud_sig:
		return
	if st == St.SYNCED:
		_set_st(St.PENDING)
	var pk := Pack.pack(body, int(Time.get_unix_time_from_system()))
	if pk.err == "":
		_js.stage(JSON.stringify(pk.items))


## 上传时机（一局结算 / 回到标题 / 设置面板关闭）：有待上传的内容才排一次同步（去抖、受退避约束）
func flush(reason: String) -> void:
	if _js == null or not active():
		return
	if not pending() and st != St.FAILED:
		return
	_log("排队同步：" + reason)
	_schedule(DEBOUNCE)


func _schedule(delay: float) -> void:
	var at: float = maxf(_now() + delay, _next_ok)
	if _timer < 0.0 or at < _timer:
		_timer = at


func _process(_dt: float) -> void:
	if msg != "" and _now() > msg_t:
		msg = ""
		changed.emit()
	if _timer >= 0.0 and _now() >= _timer:
		_timer = -1.0
		if _busy:
			_again = true
		else:
			_start("sync")


func _start(mode: String) -> void:
	_busy = true
	_mode = mode
	_next_ok = _now() + MIN_GAP
	requests += 1
	if mode != "push":
		if mode == "sync":
			_set_st(St.SYNCING if not _ever_ok else st)
		_js.read(_cb_get)
	else:
		_upload(Cfg.cloud_body())
	changed.emit()


# ---------------------------------------------------------------- 手动入口（设置 → 存档，带确认）

## 从云端恢复：云端存档整份替换本机的进度与设置（不合并）
func pull() -> void:
	if _js == null or not can_manual():
		return
	_start("pull")


## 以本地覆盖云端：本机存档整份写到云端（不合并；云端无法读取 / 版本更新时也写）
func push() -> void:
	if _js == null or not can_manual():
		return
	_start("push")


func _say(t: String) -> void:
	msg = t
	msg_t = _now() + 4.0
	changed.emit()


# ---------------------------------------------------------------- JS 回调

func _on_probe(args: Array) -> void:
	var r := str(args[0]) if args.size() > 0 else ""
	if r != "supported":
		_log("不可用：" + r)
		_set_st(St.OFF)
		return
	supported = true
	_start("sync")


func _on_get(args: Array) -> void:
	var code := str(args[0]) if args.size() > 0 else "err"
	var data := str(args[1]) if args.size() > 1 else ""
	if code != "ok":
		_on_err(data)
		return
	var items = Pack.parse(data)
	var res := Pack.unpack(items if items is Dictionary else {})
	if _mode == "pull":
		_busy = false
		if res.status == "ok":
			Cfg.cloud_apply(res.body)
			Cfg.cloud_sig = Pack.sig(Cfg.cloud_body())
			Cfg.save()
			Cfg.apply()
			_ever_ok = true
			_set_st(St.SYNCED)
			_say("已从云端恢复")
		else:
			_say("云端没有可用的存档" if res.status != "newer" else "云端存档来自更新的版本")
			changed.emit()
		return
	match res.status:
		"newer", "bad":
			_busy = false
			_ever_ok = true
			err_text = res.err
			_log("云端存档不可用（%s）：%s；本地照旧，不自动上传" % [res.status, res.err])
			_js.stage("")
			_set_st(St.NEWER if res.status == "newer" else St.BAD)
			return
	var local := Cfg.cloud_body()
	var merged := Pack.merge(local, res.body)
	if Pack.canon(merged) != Pack.canon(local):
		Cfg.cloud_apply(merged)
		Cfg.save()   # 写回本地（st 仍是 SYNCING / busy，local_saved 不会排上传）
		Cfg.apply()
		_log("合并了云端存档")
	if res.status == "ok" and Pack.canon(merged) == Pack.canon(res.body):
		_done_ok(Pack.sig(merged))
		return
	_upload(merged)


func _upload(body: Dictionary) -> void:
	var pk := Pack.pack(body, int(Time.get_unix_time_from_system()))
	if pk.err != "":
		_busy = false
		err_text = "存档超过 %d 片" % Pack.MAX_CHUNKS
		_log(err_text)
		_set_st(St.FAILED)
		return
	_up_sig = Pack.sig(body)
	if _mode == "sync":
		requests += 1
	_js.write(JSON.stringify(pk.items), _cb_set)


func _on_set(args: Array) -> void:
	var code := str(args[0]) if args.size() > 0 else "err"
	if code != "ok":
		_on_err(str(args[1]) if args.size() > 1 else "")
		return
	_js.stage("")
	if _mode == "push":
		_say("已覆盖云端存档")
	_done_ok(_up_sig)


func _done_ok(sig: String) -> void:
	_busy = false
	_ever_ok = true
	_rl_n = 0
	_err_n = 0
	err_text = ""
	if Cfg.cloud_sig != sig:
		Cfg.cloud_sig = sig
		Cfg.save()   # 记下与云端一致的签名（落盘，下次启动据此判断待上传）
	_set_st(St.SYNCED)
	if _again or pending():
		_again = false
		_set_st(St.PENDING)
		_schedule(DEBOUNCE)


func _on_err(info: String) -> void:
	_busy = false
	var e = Pack.parse(info)
	var code := int(e.get("code", 0)) if e is Dictionary and (e.get("code") is float or e.get("code") is int) else 0
	err_text = info
	if code == RATE_LIMIT:
		_rl_n += 1
		var d: float = minf(RL_BASE * pow(2.0, _rl_n - 1), RL_MAX)
		_log("限流（307044），%.0f 秒后重试" % d)
		_next_ok = _now() + d
		if _mode == "sync":
			if st == St.SYNCING and not _ever_ok:
				pass   # 启动同步被限流：保持「同步中」，退避后重读
			else:
				_set_st(St.PENDING)
			_schedule(0.0)
		else:
			_say("请求过于频繁，稍后再试")
		return
	if not _ever_ok and _mode == "sync":
		_log("读取云端失败，按未登录处理：" + info)
		_set_st(St.OFFLINE)
		return
	if _mode != "sync":
		_say("操作失败，稍后再试")
		return
	_err_n += 1
	var d2: float = minf(ERR_BASE * pow(2.0, _err_n - 1), ERR_MAX)
	_log("同步失败，%.0f 秒后重试：%s" % [d2, info])
	_next_ok = _now() + d2
	_set_st(St.FAILED)
	_schedule(0.0)
