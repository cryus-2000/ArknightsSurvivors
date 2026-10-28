extends Node
## 战绩分享卡的 Toy SDK 接入（网页端薄封装 tools/web/share.js，window.__syShare）：
##   头像昵称 toy.getUserProfile（打开分享卡时取一次，用户拒绝就不画）、二维码 toy.getQrCode、
##   保存 toy.saveImageToAlbum（B站 App 内），不支持时退回 <a download>；一律先 isSupport（share.js 的 probe）。
## 隐私：头像昵称只在本地画卡，不上传、不写日志；toyOpenId 在 JS 侧就不读。
## 非网页（桌面版）：没有头像 / 二维码，保存写到「图片/方舟幸存者/」。itch 网页包：probe 全 false，保存走浏览器下载。
const ShareCard = preload("res://scripts/screens/share_card.gd")

class CardCanvas extends Control:
	var card
	var d: Dictionary
	func _draw() -> void:
		card.draw(self, d, Vector2.ZERO, 1.0)

var g
var _js = null
var _cbs: Array = []          # JavaScriptBridge 回调要一直持有，不然被回收
var sup := {"profile": false, "qr": false, "album": false}
var avatar: Texture2D
var nickname := ""
var qr: Texture2D
var _asked := false
var busy := false
var status := ""              # 分享浮层上的一行状态（保存结果）
var out_dir := ""             # 测试 / 录像用：桌面版保存改写到这里（缺省 = 图片/方舟幸存者）


func setup(game) -> void:
	g = game
	if not OS.has_feature("web"):
		return
	_js = JavaScriptBridge.get_interface("__syShare")
	if _js == null:
		return
	_js.probe(_cb(_on_probe))


func _cb(f: Callable) -> JavaScriptObject:
	var c := JavaScriptBridge.create_callback(f)
	_cbs.append(c)
	return c


func _on_probe(args: Array) -> void:
	var r = JSON.parse_string(str(args[0])) if args.size() > 0 else null
	if r is Dictionary:
		for k in sup:
			sup[k] = bool(r.get(k, false))
	if sup.qr:
		_js.qr(256, _cb(_on_qr))
	want_profile()


## 打开分享卡时调（紧跟玩家点按，平台的数据确认弹窗要用户操作触发）：每局只问一次
func want_profile() -> void:
	if _js == null or not sup.profile or _asked:
		return
	_asked = true
	_js.profile(_cb(_on_profile))


func _on_profile(args: Array) -> void:
	if args.size() < 2 or str(args[0]) != "ok":
		return   # 拒绝 / 失败：不画头像昵称
	var r = JSON.parse_string(str(args[1]))
	if not (r is Dictionary):
		return
	nickname = str(r.get("nickname", "")).substr(0, 16)
	avatar = _png(str(r.get("avatar", "")))
	_redraw()


func _on_qr(args: Array) -> void:
	if args.size() >= 2 and str(args[0]) == "ok":
		qr = _png(str(args[1]))
		_redraw()


func _png(b64: String) -> Texture2D:
	if b64 == "":
		return null
	var img := Image.new()
	if img.load_png_from_buffer(Marshalls.base64_to_raw(b64)) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _redraw() -> void:
	if g != null and is_instance_valid(g.hud):
		g.hud.queue_redraw()


## 卡面数据补上头像 / 昵称 / 二维码（拿不到的留空，share_card 自己退回占位）
func fill(d: Dictionary) -> Dictionary:
	d.avatar = avatar
	d.qr = qr
	if nickname != "":
		d.name = nickname
	return d


## 保存：在 600×800 的离屏视口里画一遍卡面 → PNG → 网页交给 share.js，桌面写文件
func save(card, d: Dictionary) -> void:
	if busy:
		return
	busy = true
	status = "正在生成图片……"
	_redraw()
	var vp := SubViewport.new()
	vp.size = Vector2i(int(ShareCard.W), int(ShareCard.H))
	vp.transparent_bg = false
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST   # 子视口缺省线性过滤，像素字 / 立绘会糊
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var c := CardCanvas.new()
	c.card = card
	c.d = d
	c.size = Vector2(ShareCard.W, ShareCard.H)
	vp.add_child(c)
	add_child(vp)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var png: PackedByteArray = vp.get_texture().get_image().save_png_to_buffer()
	vp.queue_free()
	if _js != null:
		_js.save(Marshalls.raw_to_base64(png), _cb(_on_saved))
		return
	var dir := out_dir
	if dir == "":
		dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
		if dir == "":
			dir = OS.get_user_data_dir()
		dir = dir.path_join("方舟幸存者")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("战绩_%s.png" % Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		status = "保存失败"
	else:
		f.store_buffer(png)
		f.close()
		status = "已保存到 图片/方舟幸存者"
	busy = false
	_redraw()


func _on_saved(args: Array) -> void:
	var r := str(args[0]) if args.size() > 0 else "err"
	status = {"album": "已保存到相册", "download": "已开始下载图片"}.get(r, "保存失败")
	busy = false
	_redraw()
