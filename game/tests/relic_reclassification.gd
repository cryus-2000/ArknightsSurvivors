extends Node

const DB = preload("res://scripts/core/relic_db.gd")

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var db = DB.new()
	db.load_files()
	assert(db.implemented().size() == 265, "Review must cover all implemented relics (docs/57: all 262 + docs/74: 263-265)")
	assert(db.get_relic("265").rarity == "稀有" and db.get_relic("265").lane == "multi", "穿甲弹（10-23）：稀有、多弹火力（docs/197）")
	assert(db.get_relic("79").rarity == "稀有", "Global damage +20% is rare")
	assert(db.get_relic("89").rarity == "核心", "Global SP +30% is core")
	assert(db.price("79") == 14, "Default price follows resolved rarity")
	assert(db.price("89") == 20, "Default price follows resolved rarity")
	assert(db.get_relic("118").rarity == "稀有")
	assert(db.get_relic("199").rarity == "基础", "Extra shield capacity requires the shield engine")
	for r in db.implemented():
		assert(db.lane_names.has(r.lane), "Missing lane classification (docs/197): " + r.id)
		assert(db.price(r.id) == maxi(1, DB.PRICE[r.rarity]), "Rarity and price drift: " + r.id)
	assert(db.implemented().filter(func(r): return r.rarity == "升华").size() >= 3, "Ascension pool should remain viable")
	assert(db.get_relic("221").source == "event")
	assert(db.get_relic("216").rarity == "遭诅古物")
	print("RELIC_RECLASSIFICATION_OK %d reviewed; lanes, prices and ascension pool checked" % db.implemented().size())
	get_tree().quit()
