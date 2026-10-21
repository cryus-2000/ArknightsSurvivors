extends Node
## 第一位商人预告（run/shop.gd prepare_first / sync_preview / preview_item，docs/119 §4.5）的回归：
##   godot --headless --path game res://tests/merchant_build_offer_test.tscn -- --regression --balance --seed=1 --op=skadi --squad=kaltsit
## 第 5 帧模拟商人生成：出现时固定货架与价格（进店不重抽、取消进店不重抽）、联动位保证、预告价格随成交涨价同步、
## 售出撤销、付费刷新后同步、离开撤销、第二位商人不预告、开关关不提前抽货。全部通过打印 "MERCHANT BUILD OFFER failures=0"。

const Bal = preload("res://scripts/core/balance.gd")
const BA = preload("res://scripts/run/build_affinity.gd")

var game: Node
var shop
var frames := 0
var n := 0
var fails := 0


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _process(_d: float) -> void:
	frames += 1
	if frames != 5:
		return
	shop = game.shop_sys
	if not Bal._data.has("build"):
		Bal._data["build"] = {}
	Bal._data["build"]["merchant_preview"] = 1
	Bal._data["build"]["affinity_ui"] = 1
	test_first_merchant()
	test_refresh_and_leave()
	test_second_and_off()
	print("%d checks, %d failed" % [n, fails])
	print("MERCHANT BUILD OFFER failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func ids() -> Array:
	return game.shop_items.map(func(it): return str(it.id))


## 像 spawner 那样生成第 idx 位商人
func spawn_merchant(idx: int) -> void:
	game.merchant_idx = idx
	game.merchant = {"pos": game.ppos + Vector2(200, 0), "life": 60.0, "near": false, "purchases": 0}
	game.shop_items.clear()
	game.shop_refreshed = false
	shop.prepare_first()


func preview_index() -> int:
	if game.merchant.is_empty() or not game.merchant.has("preview"):
		return -1
	for i in game.shop_items.size():
		if str(game.shop_items[i].id) == str(game.merchant.preview):
			return i
	return -1


func test_first_merchant() -> void:
	game.ingots = 9
	spawn_merchant(1)
	ok(game.shop_items.size() == 5, "第一位商人生成时货架已定：3 件藏品 + 急救包 + 灯油（%d）" % game.shop_items.size())
	var first := ids()
	var pi := preview_index()
	ok(pi >= 0, "有联动候选（斯卡蒂反手斩 / Mon3tr → 追击链；技能链 85）：预告存在（%s）" % [first])
	if pi >= 0:
		var it: Dictionary = game.shop_items[pi]
		ok(BA.chain_of(str(it.id)) != "" and game.RL[it.id].rarity in ["基础", "稀有"], "预告商品是三条链里的基础 / 稀有（%s %s）" % [it.id, game.RL[it.id].rarity])
		ok(game.progression.affinity.relic_live(str(it.id)), "预告商品当前有在队干员能触发")
		var pv: Dictionary = shop.preview_item()
		ok(pv.price == int(it.price) and pv.have == 9 and pv.short == maxi(0, int(it.price) - 9), "预告读货架现价与持有 / 差额（%s）" % [pv])
		ok(shop.preview_text().contains(game.RL[it.id].name) and shop.preview_text().contains("差 "), "预告文字含商品名与差额（%s）" % shop.preview_text())
	# 进店不重抽
	game.state = game.S.PLAY
	shop.open()
	ok(ids() == first, "进店不重抽：货架与生成时相同")
	# 取消进店（离开不买）再进：仍相同
	shop.close()
	ok(not game.merchant.is_empty() and ids() == first, "离开不买：商人还在、货架不变")
	shop.open()
	ok(ids() == first, "再进店仍是同一货架")
	# 买别的东西：预告价格随成交涨价同步
	if pi >= 0:
		var pv0: Dictionary = shop.preview_item()
		var other := -1
		for i in game.shop_items.size():
			if i != pi and game.shop_items[i].kind == "relic":
				other = i
				break
		game.ingots = 999
		shop.buy(other)
		var pv1: Dictionary = shop.preview_item()
		ok(game.shop_items[other].sold and pv1.price > pv0.price and pv1.price == int(game.shop_items[pi].price), "买了别件后预告价格同步涨价（%d → %d）" % [pv0.price, pv1.price])
		ok(pv1.short == 0 and shop.preview_text().contains("可买"), "持有足够时写「可买」")
		# 买预告商品：撤销
		shop.buy(pi)
		ok(game.shop_items[pi].sold and shop.preview_item().is_empty() and shop.preview_text() == "", "预告商品售出即撤销预告")
	shop.close()
	game.state = game.S.PLAY


func test_refresh_and_leave() -> void:
	game.merchant = {}
	game.shop_items.clear()
	game.ingots = 50
	spawn_merchant(1)
	var before := ids()
	game.state = game.S.PLAY
	shop.open()
	shop.refresh()
	ok(game.shop_refreshed and ids() != before, "付费刷新：整个货架重抽")
	var pi := preview_index()
	if pi >= 0:
		ok(not game.shop_items[pi].sold and BA.chain_of(str(game.shop_items[pi].id)) != "", "刷新后预告指向新货架上的联动商品")
	else:
		ok(not game.merchant.has("preview") and shop.preview_text() == "", "刷新后新货架没有联动商品：预告撤销")
	shop.close()
	game.state = game.S.PLAY
	# 商人离开：预告随之消失
	game.merchant.life = 0.0
	shop.update(0.1)
	ok(game.merchant.is_empty() and shop.preview_text() == "", "商人离开：预告撤销")


func test_second_and_off() -> void:
	game.shop_items.clear()
	spawn_merchant(2)
	ok(game.shop_items.is_empty() and not game.merchant.has("preview") and shop.preview_text() == "", "第二位商人：生成时不抽货、无预告")
	game.merchant = {}
	Bal._data["build"]["merchant_preview"] = 0
	spawn_merchant(1)
	ok(game.shop_items.is_empty() and not game.merchant.has("preview"), "开关关：第一位商人生成时不提前抽货")
	game.state = game.S.PLAY
	shop.open()
	ok(game.shop_items.size() == 5 and not game.merchant.has("preview"), "开关关：进店才抽，仍无预告")
	shop.close()
	game.state = game.S.PLAY
	Bal._data["build"]["merchant_preview"] = 1
