extends RefCounted
## 商人与商店（逻辑）：商人按时间表出现、进出商店、货架刷新与定价、购买结算。
## 商店界面（卡片 / 按钮 / 背景）在 screens/ 下。2026-09-26 从 game.gd 拆出。

const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game


func _init(game: Game) -> void:
	g = game


func update(dt: float) -> void:
	if trader:
		return   # 诡意行商卡的一次商店开着：地图上的商人不走倒计时
	if g.merchant.is_empty():
		g.merchant_light.visible = false
		return
	g.merchant.pos = g.spawner.safe_event_pos(g.merchant.pos, 100.0)
	g.merchant.life -= dt
	# 离开前 15 秒提醒一次（音效；文字横幅 10-22b 用户取消）
	if g.merchant.life <= 15.0 and not g.merchant.get("warned", false):
		g.merchant.warned = true
		Sfx.play("ui_move", -2.0, 0.8)
	g.merchant_light.visible = true
	g.merchant_light.position = g.merchant.pos + g.vfx.merchant_goods()   # 暖光在身前货物上（10-21 新商人没有提灯）
	var d: float = g.merchant.pos.distance_to(g.ppos)
	if d < 46.0 and not g.merchant.near:
		g.merchant.near = true
		open()
	elif d > 90.0:
		g.merchant.near = false
	if g.merchant.life <= 0.0 and g.state == g.S.PLAY:
		g.merchant = {}
		g.vfx.show_banner("商人离开了")


## 商人倒计时颜色：最后 15 秒红色闪烁
func merchant_col() -> Color:
	if g.merchant.is_empty() or g.merchant.life > 15.0:
		return UI.GOLD
	return UI.GOLD.lerp(UI.RED, 0.5 + 0.5 * sin(g.t * 8.0))


## 后两拨涨价；本次每成交一件，其余货品递增。折扣仍由藏品层统一提供。
func price_mult() -> float:
	var visit: int = clampi(g.merchant_idx, 1, 3)
	var wave: float = [1.0, Bal.v("shop/second_visit_mult", 1.5), Bal.v("shop/third_visit_mult", 2.0)][visit - 1]
	var bought: int = trader_buys if trader else int(g.merchant.get("purchases", 0))
	return g.shop_price_mult * wave * (1.0 + bought * Bal.v("shop/purchase_step", 0.2))


## 商店抬头的涨价说明（跟旋钮走，不写死）
func step_note() -> String:
	var s := "每购一件余货 +%d%%" % int(round(Bal.v("shop/purchase_step", 0.2) * 100.0))
	var rs: float = Bal.v("shop/relic_step", 0.3)
	if rs > 0.0:
		s += "，藏品再 +%d%%" % int(round(rs * 100.0))
	return s


## 藏品价格倍率：在 price_mult 之上，本次每买一件藏品，余下藏品再 +shop/relic_step（docs/191：商人处连买藏品是高峰来源，用涨价做软限制，不设件数上限）
func relic_mult() -> float:
	var nb: int = trader_buys if trader else int(g.merchant.get("relic_purchases", 0))
	return price_mult() * (1.0 + nb * Bal.v("shop/relic_step", 0.3))


## 每次商人可买藏品件数；balance shop/relic_buy_limit < 0 = 不限（用户 10-11：取消硬上限，只靠「每购一件余货 +20%」和藏品栏容量软限制）
func relic_buy_unlimited() -> bool:
	return Bal.vi("shop/relic_buy_limit", -1) < 0


func relic_buys_left() -> int:
	if relic_buy_unlimited():
		return 999
	return maxi(0, Bal.vi("shop/relic_buy_limit", -1) - int(g.merchant.get("relic_purchases", 0)))


func can_buy(it: Dictionary) -> bool:
	return not it.sold and g.ingots >= it.price and (it.kind != "relic" or (relic_buys_left() > 0 and g.progression.can_gain_relic(it.id)))


func price(kind: String) -> int:
	match kind:
		"relic":
			return int(ceil(14 * price_mult()))
		"heal":
			return int(ceil(6 * price_mult()))
		"oil":
			return int(ceil(5 * price_mult()))
		"refresh":
			return int(ceil(3 * price_mult()))
	return 0


## first = 第一位商人的首轮货架（docs/119 §4.5）：合法池里有「基础 / 稀有、三条链、当前有在队干员能触发」的藏品时保证一件（顶掉第三格），
## 其余照原规则；没有就不动。付费刷新不带 first（不重复保证）
func roll(first := false) -> void:
	g.shop_items.clear()
	var pool: Array = g.progression.relic_pool_ids(true)
	if trader:
		# 诡意行商卡（docs/184 §3）：前两格换成主流派里排最前的两件（只重排，不多取随机数）
		var ml: String = g.endg.main_lane()
		var on_lane: Array = pool.filter(func(id): return str(g.RL[id].get("lane", "")) == ml).slice(0, 2)
		pool = on_lane + pool.filter(func(id): return not on_lane.has(id))
	var slots: int = 3
	for i in min(slots, pool.size()):
		var r: Dictionary = g.RL[pool[i]]
		g.shop_items.append({"kind": "relic", "id": pool[i], "name": ("【遭诅】" if r.rarity == "遭诅古物" else "") + g.rfx.display_name(pool[i]), "desc": g.rfx.display_desc(pool[i]), "full": g.rfx.display_desc(pool[i], true), "price": g.rfx.db.price(pool[i], relic_mult()), "sold": false})
	if first:
		var link: String = g.progression.affinity.merchant_link_pick(pool)
		if link != "" and not g.shop_items.any(func(it): return it.id == link) and not g.shop_items.is_empty():
			g.shop_items[g.shop_items.size() - 1] = {"kind": "relic", "id": link, "name": g.rfx.display_name(link), "desc": g.rfx.display_desc(link), "full": g.rfx.display_desc(link, true), "price": g.rfx.db.price(link, relic_mult()), "sold": false}
	# 深蓝线：商店多一栏必为遭诅古物（深海的馈赠）
	if g.rfx.rule("deep_sea") > 0:
		var cursed: Array = pool.filter(func(id): return g.RL[id].rarity == "遭诅古物" and not g.shop_items.any(func(it): return it.id == id))
		if not cursed.is_empty():
			var cid: String = cursed[0]
			g.shop_items.append({"kind": "relic", "id": cid, "name": "【遭诅】" + g.rfx.display_name(cid), "desc": g.rfx.display_desc(cid), "full": g.rfx.display_desc(cid, true), "price": g.rfx.db.price(cid, relic_mult()), "sold": false, "deep": true})
	if g.mode == g.Mode.BALANCE:
		g.dbg_relic_offer.append([int(g.t), "shop", g.shop_items.map(func(it): return it.id)])
	g.shop_items.append({"kind": "heal", "id": "heal", "name": "急救包", "desc": "回复 40% 最大生命", "price": price("heal"), "sold": false})
	g.shop_items.append({"kind": "oil", "id": "oil", "name": "灯油", "desc": "灯火 +50", "price": price("oil"), "sold": false})


## ---- 第一位商人预告（docs/119 §4.5）：生成时就定下首轮货架与价格（到店不再抽），HUD 指示写出联动商品、价格、持有源石锭与差额。
## 只影响第一位商人；开关 build/merchant_preview = 0 时不提前抽货（随机数消耗与改前相同）
func preview_on() -> bool:
	return g.merchant_idx == 1 and Bal.vi("build/merchant_preview", 1) != 0


func prepare_first() -> void:
	if not preview_on() or g.merchant.is_empty():
		return
	roll(true)
	sync_preview()


## 预告 = 货架上第一件「三条链、基础 / 稀有、当前有在队干员能触发、未售出」的藏品；没有就撤掉预告
func sync_preview() -> void:
	if g.merchant.is_empty():
		return
	g.merchant.erase("preview")
	if not preview_on():
		return
	var af = g.progression.affinity
	for it in g.shop_items:
		if it.kind == "relic" and not it.sold and af.chain_of(str(it.id)) != "" and g.RL[it.id].rarity in ["基础", "稀有"] and af.relic_live(str(it.id)):
			g.merchant["preview"] = str(it.id)
			return


## HUD 读的预告：{name, price, have, short}（价格从当前货架读，成交涨价后同步）；没有预告返回空字典
func preview_item() -> Dictionary:
	if g.merchant.is_empty() or not g.merchant.has("preview"):
		return {}
	for it in g.shop_items:
		if it.kind == "relic" and str(it.id) == str(g.merchant.preview) and not it.sold:
			return {"name": g.RL[it.id].name, "price": int(it.price), "have": g.ingots, "short": maxi(0, int(it.price) - g.ingots)}
	return {}


## 预告文字（HUD 指示 / 横幅）："「炸裂之手」14 锭，持有 9，差 5" / "…持有 20，可买"（手机一行要放得下，用短式）
func preview_text() -> String:
	var pv := preview_item()
	if pv.is_empty():
		return ""
	return "「%s」%d 锭，持有 %d，%s" % [pv.name, pv.price, pv.have, ("差 %d" % pv.short) if pv.short > 0 else "可买"]


func open() -> void:
	if g.shop_items.is_empty():
		roll()
	g.state = g.S.SHOP
	Sfx.play("relic", -4.0)
	if g.mode != g.Mode.PLAY:
		print("SHOP ", g.shop_items.map(func(it): return it.name))
	g.shop_ui.build(true)


func buy(i: int) -> void:
	if g.state != g.S.SHOP or i < 0 or i >= g.shop_items.size():
		return
	var it: Dictionary = g.shop_items[i]
	if it.sold or g.ingots < it.price or (it.kind == "relic" and relic_buys_left() <= 0):
		Sfx.play("ui_move", -2.0, 0.6)
		return
	# 库存可能在事件中变满；确认可拿到藏品再收费，避免空买。
	if it.kind == "relic" and not g.progression.can_gain_relic(it.id):
		Sfx.play("ui_move", -2.0, 0.6)
		g.vfx.show_banner("藏品空间已为结局事件预留；可以升级已有藏品")
		return
	g.ingots -= it.price
	g.telemetry.ingots_spent += it.price   # 作战记录（docs/77）
	it.sold = true
	if trader:
		trader_buys += 1
	elif not g.merchant.is_empty():
		g.merchant["bought"] = true
		g.merchant["purchases"] = int(g.merchant.get("purchases", 0)) + 1
	match it.kind:
		"relic":
			if not trader:
				g.merchant["relic_purchases"] = int(g.merchant.get("relic_purchases", 0)) + 1
			g.progression.gain_relic(it.id, "shop")
		"heal":
			g.combat.heal(g.max_hp * 0.4, "商店")
		"oil":
			var l0: float = g.lamp
			g.lamp = min(g.lamp_cap, g.lamp + 50.0)
			g.telemetry.lamp_note("商人", g.lamp - l0)
	for item in g.shop_items:
		if not item.sold:
			item.price = g.rfx.db.price(item.id, relic_mult()) if item.kind == "relic" else price(item.kind)
	# 预告的商品售出即撤销（docs/119 §4.5）；预告价格由 preview_item 从货架现价读，这里不用改
	if not trader and not g.merchant.is_empty() and g.merchant.has("preview") and str(g.merchant.preview) == str(it.id):
		g.merchant.erase("preview")
	Sfx.play("ui_ok")
	g.shop_ui.build()


## 认知塑造「自我审视」：每局一次免费刷新还没用掉
func refresh_free() -> bool:
	return g.rfx.rule("shop_free_refresh") > 0


func refresh() -> void:
	if g.shop_refreshed or (not refresh_free() and g.ingots < price("refresh")):
		return
	g.shop_refreshed = true
	if refresh_free():
		g.rfx.use_rule("shop_free_refresh")
	else:
		g.telemetry.ingots_spent += price("refresh")
		g.ingots -= price("refresh")
	roll()
	sync_preview()   # 刷新后同步预告：按新货架重定，不保证联动位、不留旧商品
	Sfx.play("relic", -6.0)
	g.shop_ui.build(true)


## 诡意行商卡（用户 10-28「原作诡意行商是进一次商店」，docs/184 §3）：翻开即打开一次商店，货架同商人（价格按当前是第几拨商人）、
## 前两格主流派；关掉即结束，路口二之后没有商人也能用。地图上若正有一位商人，它和它的货架不动（货架先收起，关店后放回）
var trader := false
var trader_buys := 0
var _trader_stash: Dictionary = {}


func open_trader() -> void:
	_trader_stash = {"items": g.shop_items, "refreshed": g.shop_refreshed}
	trader = true
	trader_buys = 0
	g.shop_items = []
	g.shop_refreshed = false
	g.panel.visible = true
	open()


func close() -> void:
	for c in g.panel.get_children():
		if c.has_meta("shopbtn"):
			c.queue_free()
	g.panel.visible = false
	g.state = g.S.PLAY
	g.combat.panel_grace()   # 离开商人：0.8 秒保护
	Sfx.play("ui_ok", -4.0)
	if trader:
		trader = false
		g.shop_items = _trader_stash.get("items", [])
		g.shop_refreshed = bool(_trader_stash.get("refreshed", false))
		_trader_stash = {}
		g.vfx.show_banner("诡意行商收起货摊离开了")
		g.check_pending()
		return
	# 交易过就离开，避免走回去反复触发；等下一次出现
	if not g.merchant.is_empty() and g.merchant.get("bought", false):
		g.vfx.sparks(g.merchant.pos, Vector2.UP, UI.GOLD, 12, 160.0)
		g.merchant = {}
		g.shop_items.clear()
		g.vfx.show_banner("商人收好源石锭，离开了")
