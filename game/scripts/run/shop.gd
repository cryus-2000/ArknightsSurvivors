extends RefCounted
## 商人与商店（逻辑）：商人按时间表出现、进出商店、货架刷新与定价、购买结算。
## 商店界面（卡片 / 按钮 / 背景）在 screens/ 下。2026-09-26 从 game.gd 拆出。

const UI = preload("res://scripts/ui.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game


func _init(game: Game) -> void:
	g = game


func update(dt: float) -> void:
	if g.merchant.is_empty():
		g.merchant_light.visible = false
		return
	g.merchant.life -= dt
	# 离开前 15 秒提醒一次（横幅 + 音效），之后倒计时变红闪烁
	if g.merchant.life <= 15.0 and not g.merchant.get("warned", false):
		g.merchant.warned = true
		g._show_banner("商人 15 秒后离开 —— 还没交易就快去")
		Sfx.play("ui_move", -2.0, 0.8)
	g.merchant_light.visible = true
	g.merchant_light.position = g.merchant.pos + Vector2(10, -10)
	var d: float = g.merchant.pos.distance_to(g.ppos)
	if d < 46.0 and not g.merchant.near:
		g.merchant.near = true
		open()
	elif d > 90.0:
		g.merchant.near = false
	if g.merchant.life <= 0.0 and g.state == g.S.PLAY:
		g.merchant = {}
		g._show_banner("商人离开了")


## 商人倒计时颜色：最后 15 秒红色闪烁
func merchant_col() -> Color:
	if g.merchant.is_empty() or g.merchant.life > 15.0:
		return UI.GOLD
	return UI.GOLD.lerp(UI.RED, 0.5 + 0.5 * sin(g.t * 8.0))


func price(kind: String) -> int:
	match kind:
		"relic":
			return 14
		"heal":
			return int(ceil(6 * g.shop_price_mult))
		"oil":
			return int(ceil(5 * g.shop_price_mult))
		"refresh":
			return int(ceil(3 * g.shop_price_mult))
	return 0


func roll() -> void:
	g.shop_items.clear()
	var pool: Array = g._relic_pool_ids(true)
	for i in min(3, pool.size()):
		var r: Dictionary = g.RL[pool[i]]
		g.shop_items.append({"kind": "relic", "id": pool[i], "name": ("【遭诅】" if r.rarity == "遭诅古物" else "") + g.rfx.display_name(pool[i]), "desc": g.rfx.display_desc(pool[i]), "price": g.rfx.db.price(pool[i], g.shop_price_mult), "sold": false})
	# 深蓝线：商店多一栏必为遭诅古物（深海的馈赠）
	if g.rfx.rule("deep_sea") > 0:
		var cursed: Array = pool.filter(func(id): return g.RL[id].rarity == "遭诅古物" and not g.shop_items.any(func(it): return it.id == id))
		if not cursed.is_empty():
			var cid: String = cursed[0]
			g.shop_items.append({"kind": "relic", "id": cid, "name": "【遭诅】" + g.rfx.display_name(cid), "desc": g.rfx.display_desc(cid), "price": g.rfx.db.price(cid, g.shop_price_mult), "sold": false, "deep": true})
	if g.balance:
		g.dbg_relic_offer.append([int(g.t), "shop", g.shop_items.map(func(it): return it.id)])
	g.shop_items.append({"kind": "heal", "id": "heal", "name": "急救包", "desc": "回复 40% 最大生命", "price": price("heal"), "sold": false})
	g.shop_items.append({"kind": "oil", "id": "oil", "name": "灯油", "desc": "灯火 +50", "price": price("oil"), "sold": false})


func open() -> void:
	if g.shop_items.is_empty():
		roll()
	g.state = g.S.SHOP
	Sfx.play("relic", -4.0)
	if g.autotest:
		print("SHOP ", g.shop_items.map(func(it): return it.name))
	g._build_shop_ui()


func buy(i: int) -> void:
	if g.state != g.S.SHOP or i >= g.shop_items.size():
		return
	var it: Dictionary = g.shop_items[i]
	if it.sold or g.ingots < it.price:
		Sfx.play("ui_move", -2.0, 0.6)
		return
	g.ingots -= it.price
	it.sold = true
	if not g.merchant.is_empty():
		g.merchant["bought"] = true
	match it.kind:
		"relic":
			g._gain_relic(it.id)
		"heal":
			g._heal(g.max_hp * 0.4, "拾取")
		"oil":
			g.lamp = min(g.lamp_cap, g.lamp + 50.0)
	Sfx.play("ui_ok")
	g._build_shop_ui()


func refresh() -> void:
	if g.shop_refreshed or g.ingots < price("refresh"):
		return
	g.shop_refreshed = true
	g.ingots -= price("refresh")
	roll()
	Sfx.play("relic", -6.0)
	g._build_shop_ui()


func close() -> void:
	for c in g.panel.get_children():
		if c.has_meta("shopbtn"):
			c.queue_free()
	g.panel.visible = false
	g.state = g.S.PLAY
	Sfx.play("ui_ok", -4.0)
	# 交易过就离开，避免走回去反复触发；等下一次出现
	if not g.merchant.is_empty() and g.merchant.get("bought", false):
		g._sparks(g.merchant.pos, Vector2.UP, UI.GOLD, 12, 160.0)
		g.merchant = {}
		g.shop_items.clear()
		g._show_banner("商人收好源石锭，离开了")
